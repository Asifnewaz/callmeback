#!/bin/bash
# ╔═══════════════════════════════════════════════════════════════════╗
# ║              callmeback  —  Installer                            ║
# ║   Notifies you when Claude Code finishes a task                  ║
# ╚═══════════════════════════════════════════════════════════════════╝
#
#  Install:
#    curl -fsSL https://raw.githubusercontent.com/Asifnewaz/callmeback/main/install.sh | bash
#
#  Uninstall:
#    curl -fsSL https://raw.githubusercontent.com/Asifnewaz/callmeback/main/install.sh | bash -s -- --uninstall

set -e

# ── Colours ──────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m';     RESET='\033[0m'

ok()   { echo -e "${GREEN}  ✔  $*${RESET}"; }
info() { echo -e "${CYAN}  →  $*${RESET}"; }
warn() { echo -e "${YELLOW}  ⚠  $*${RESET}"; }
err()  { echo -e "${RED}  ✘  $*${RESET}"; exit 1; }
hr()   { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

# KEY FIX: read from /dev/tty so curl-pipe works
ask() {
  local __var=$1 __prompt=$2 __val
  printf "%s" "$__prompt" >&2
  read -r __val </dev/tty
  printf -v "$__var" '%s' "$__val"
}

CLAUDE_DIR="$HOME/.claude"
BEEP_SCRIPT="$CLAUDE_DIR/claude-done-beep.sh"
STOP_SCRIPT="$CLAUDE_DIR/claude-stop-beep.sh"
CONFIG_FILE="$CLAUDE_DIR/beep-config.sh"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
REPO_RAW="https://raw.githubusercontent.com/Asifnewaz/callmeback/main"

# ── Uninstall ─────────────────────────────────────────────────────────
if [[ "${1:-}" == "--uninstall" ]]; then
  echo ""; hr
  echo -e "${BOLD}  callmeback  —  Uninstaller${RESET}"; hr; echo ""
  rm -f "$BEEP_SCRIPT" "$STOP_SCRIPT" "$CONFIG_FILE"
  if [[ -f "$SETTINGS_FILE" ]] && command -v python3 &>/dev/null; then
    python3 - "$SETTINGS_FILE" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f: cfg = json.load(f)
    hooks = cfg.get("hooks", {})
    for event in ["Stop", "PreToolUse"]:
        if event in hooks:
            hooks[event] = [h for h in hooks[event]
                if not any(x in str(h) for x in ["claude-done-beep","claude-stop-beep"])]
            if not hooks[event]: del hooks[event]
    if not hooks and "hooks" in cfg: del cfg["hooks"]
    with open(path, "w") as f: json.dump(cfg, f, indent=2)
    print("  Hooks removed from settings.json")
except Exception as e:
    print(f"  Could not update settings.json: {e}")
PY
  fi
  ok "callmeback uninstalled."; echo ""; exit 0
fi

# ── Header ────────────────────────────────────────────────────────────
echo ""; hr
echo -e "${BOLD}  callmeback  —  Installer${RESET}"
echo -e "  Notifies you when Claude Code finishes — so you can focus on something else"
hr; echo ""

# ── Pre-flight ────────────────────────────────────────────────────────
info "Checking requirements..."
[[ -d "$CLAUDE_DIR" ]] || mkdir -p "$CLAUDE_DIR"
if ! command -v python3 &>/dev/null; then
  warn "python3 not found — sound generation may be limited"
else
  ok "python3 found"
fi
[[ "$(uname)" == "Darwin" ]] && ok "macOS detected" || ok "Linux detected"
echo ""

# ── Inline sound preview ──────────────────────────────────────────────
preview_sound() {
  python3 - "$1" 2>/dev/null <<'PYEOF'
import struct, wave, tempfile, os, subprocess, math, sys
sound_type = sys.argv[1] if len(sys.argv) > 1 else "gentle"
rate = 44100

def sine(freq, dur, vol=0.6):
    n, fade = int(rate*dur), int(rate*0.015)
    out = []
    for i in range(n):
        s = math.sin(2*math.pi*freq*i/rate)
        if i < fade:       s *= i/fade
        elif i > n-fade:   s *= (n-i)/fade
        out.append(int(32767*vol*s))
    return out

def sine_exp(freq, dur, vol=0.6, decay=6.0):
    n = int(rate*dur)
    return [int(32767*vol*math.exp(-decay*i/n)*math.sin(2*math.pi*freq*i/rate)) for i in range(n)]

def silence(dur): return [0]*int(rate*dur)

sounds = {
    "chime":  sine(523,0.18)+sine(659,0.28),
    "bell":   sine(440,0.25,0.8),
    "pop":    sine(220,0.12,0.5)+sine(180,0.08,0.3),
    "ping":   sine(880,0.15,0.5)+sine(1047,0.2,0.4),
    "soft":   sine(330,0.20,0.28)+sine(392,0.25,0.18),
    "water":  sine_exp(1200,0.35,0.55,7.0)+silence(0.04)+sine_exp(900,0.28,0.3,9.0),
    "whoosh": [int(32767*0.3*math.sin(2*math.pi*(300+400*(i/int(rate*0.4)))*i/rate)*
               math.exp(-3.5*i/int(rate*0.4))) for i in range(int(rate*0.4))],
    "gentle": sine_exp(528,0.30,0.35,5.0)+silence(0.06)+
              sine_exp(660,0.30,0.28,5.5)+silence(0.06)+
              sine_exp(792,0.35,0.22,6.0),
}
samples = sounds.get(sound_type, sounds["gentle"])
def to_bytes(s): return b"".join(struct.pack("<h",max(-32767,min(32767,v))) for v in s)
with tempfile.NamedTemporaryFile(suffix=".wav",delete=False) as f:
    path=f.name
    with wave.open(f,"w") as wf:
        wf.setnchannels(1);wf.setsampwidth(2);wf.setframerate(rate);wf.writeframes(to_bytes(samples))
for cmd in [["afplay",path],["paplay",path],["aplay","-q",path],["pw-play",path],
            ["ffplay","-nodisp","-autoexit","-loglevel","quiet",path]]:
    try:
        if subprocess.run(cmd,capture_output=True,timeout=5).returncode==0: break
    except: continue
os.unlink(path)
PYEOF
}

# ── Step 1 — Sound selection ──────────────────────────────────────────
echo -e "${BOLD}  Step 1 of 2 — Choose a notification sound${RESET}"
echo -e "  Press the number to preview, then confirm."
echo ""
echo -e "     ${YELLOW}— Soft & gentle —${RESET}"
echo -e "  ${CYAN}1)${RESET} gentle  — Three soft ascending tones       ${YELLOW}(recommended)${RESET}"
echo -e "  ${CYAN}2)${RESET} soft    — Barely-there low hum"
echo -e "  ${CYAN}3)${RESET} water   — Water drop, quick decay"
echo -e "  ${CYAN}4)${RESET} whoosh  — Airy rising sweep"
echo ""
echo -e "     ${YELLOW}— Classic —${RESET}"
echo -e "  ${CYAN}5)${RESET} chime   — Two-tone ascending chime"
echo -e "  ${CYAN}6)${RESET} bell    — Classic single beep"
echo -e "  ${CYAN}7)${RESET} pop     — Short low pop"
echo -e "  ${CYAN}8)${RESET} ping    — Crisp high ping"
echo ""

SOUND_MAP=([1]="gentle" [2]="soft" [3]="water" [4]="whoosh" [5]="chime" [6]="bell" [7]="pop" [8]="ping")
CHOSEN_SOUND=""

while true; do
  ask SOUND_CHOICE "  Enter number [1-8]: "
  echo ""
  CHOSEN_SOUND="${SOUND_MAP[$SOUND_CHOICE]:-}"
  if [[ -z "$CHOSEN_SOUND" ]]; then
    warn "Please enter a number between 1 and 8."
    echo ""; continue
  fi
  info "Playing preview: $CHOSEN_SOUND ..."
  preview_sound "$CHOSEN_SOUND"
  echo ""
  ask CONFIRM "  Keep this sound? [Y/n]: "
  echo ""
  CONFIRM="${CONFIRM:-Y}"
  if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    ok "Sound selected: $CHOSEN_SOUND"; break
  fi
  echo ""
done

echo ""

# ── Step 2 — Repeat mode ──────────────────────────────────────────────
echo -e "${BOLD}  Step 2 of 2 — Repeat notification${RESET}"
echo ""
echo -e "  When enabled, the sound repeats every few seconds"
echo -e "  until you type your next message in Claude Code."
echo ""

ask REPEAT_CHOICE "  Enable repeat notifications? [Y/n]: "
echo ""
REPEAT_CHOICE="${REPEAT_CHOICE:-Y}"

if [[ "$REPEAT_CHOICE" =~ ^[Yy]$ ]]; then
  CHOSEN_REPEAT="on"
  ask INTERVAL_CHOICE "  Repeat every how many seconds? [default: 5]: "
  echo ""
  CHOSEN_INTERVAL="${INTERVAL_CHOICE:-5}"
  if ! [[ "$CHOSEN_INTERVAL" =~ ^[0-9]+$ ]]; then
    warn "Invalid number, defaulting to 5s."
    CHOSEN_INTERVAL="5"
  fi
  ok "Repeat: every ${CHOSEN_INTERVAL}s"
else
  CHOSEN_REPEAT="off"
  CHOSEN_INTERVAL="5"
  ok "Repeat: disabled"
fi

echo ""

# ── Download scripts ──────────────────────────────────────────────────
hr
info "Installing to $CLAUDE_DIR ..."
echo ""

curl -fsSL "$REPO_RAW/bin/claude-done-beep.sh" -o "$BEEP_SCRIPT" \
  || err "Failed to download claude-done-beep.sh — check your internet connection."

curl -fsSL "$REPO_RAW/bin/claude-stop-beep.sh" -o "$STOP_SCRIPT" \
  || err "Failed to download claude-stop-beep.sh — check your internet connection."

chmod +x "$BEEP_SCRIPT" "$STOP_SCRIPT"
ok "Scripts installed"

# ── Write config ──────────────────────────────────────────────────────
cat > "$CONFIG_FILE" <<CONF
# callmeback — Configuration
# Edit this file or use flags: bash ~/.claude/claude-done-beep.sh --help

BEEP_SOUND="$CHOSEN_SOUND"
BEEP_CUSTOM_FILE=""
BEEP_REPEAT="$CHOSEN_REPEAT"
BEEP_INTERVAL="$CHOSEN_INTERVAL"
CONF
ok "Config written"

# ── Inject hooks into settings.json ──────────────────────────────────
if [[ ! -f "$SETTINGS_FILE" ]]; then
  cat > "$SETTINGS_FILE" <<'JSON'
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "bash ~/.claude/claude-done-beep.sh" }]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "bash ~/.claude/claude-stop-beep.sh" }]
      }
    ]
  }
}
JSON
  ok "Created settings.json with hooks"
else
  python3 - "$SETTINGS_FILE" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        content = f.read().strip()
    cfg = json.loads(content) if content else {}
except Exception:
    cfg = {}
hooks = cfg.setdefault("hooks", {})
def clean(lst):
    return [h for h in lst if "claude-done-beep" not in str(h) and "claude-stop-beep" not in str(h)]
stop = clean(hooks.get("Stop", []))
stop.append({"matcher":"","hooks":[{"type":"command","command":"bash ~/.claude/claude-done-beep.sh"}]})
hooks["Stop"] = stop
pre = clean(hooks.get("PreToolUse", []))
pre.append({"matcher":"","hooks":[{"type":"command","command":"bash ~/.claude/claude-stop-beep.sh"}]})
hooks["PreToolUse"] = pre
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
print("  Hooks merged into existing settings.json")
PY
  ok "Hooks injected into settings.json"
fi

# ── Done ──────────────────────────────────────────────────────────────
echo ""
hr
echo -e "${GREEN}${BOLD}  callmeback installed!${RESET}"
hr
echo ""
echo -e "  Sound    : ${BOLD}$CHOSEN_SOUND${RESET}"
echo -e "  Repeat   : ${BOLD}$CHOSEN_REPEAT${RESET}$( [[ "$CHOSEN_REPEAT" == "on" ]] && echo " (every ${CHOSEN_INTERVAL}s)" )"
echo ""
echo -e "${BOLD}  Commands:${RESET}"
echo -e "  ${CYAN}bash ~/.claude/claude-done-beep.sh --status${RESET}          show config"
echo -e "  ${CYAN}bash ~/.claude/claude-done-beep.sh --sound gentle${RESET}    change sound"
echo -e "  ${CYAN}bash ~/.claude/claude-done-beep.sh --repeat off${RESET}      disable repeat"
echo -e "  ${CYAN}bash ~/.claude/claude-done-beep.sh --interval 10${RESET}     set interval"
echo ""
echo -e "  Uninstall:"
echo -e "  ${CYAN}curl -fsSL $REPO_RAW/install.sh | bash -s -- --uninstall${RESET}"
echo ""
