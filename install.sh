#!/bin/bash
# ╔═══════════════════════════════════════════════════════════════════╗
# ║              claude-beep  —  Installer                           ║
# ║   Notifies you with sound when Claude Code finishes a task       ║
# ╚═══════════════════════════════════════════════════════════════════╝
#
#  Install (one-liner):
#    curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/claude-beep/main/install.sh | bash
#
#  Uninstall:
#    curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/claude-beep/main/install.sh | bash -s -- --uninstall

set -e

# ── Colours ──────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m';     RESET='\033[0m'

ok()   { echo -e "${GREEN}  ✔  $*${RESET}"; }
info() { echo -e "${CYAN}  →  $*${RESET}"; }
warn() { echo -e "${YELLOW}  ⚠  $*${RESET}"; }
err()  { echo -e "${RED}  ✘  $*${RESET}"; exit 1; }
hr()   { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

CLAUDE_DIR="$HOME/.claude"
BEEP_SCRIPT="$CLAUDE_DIR/claude-done-beep.sh"
STOP_SCRIPT="$CLAUDE_DIR/claude-stop-beep.sh"
CONFIG_FILE="$CLAUDE_DIR/beep-config.sh"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

REPO_RAW="https://raw.githubusercontent.com/YOUR_USERNAME/claude-beep/main"

# ── Uninstall mode ────────────────────────────────────────────────────
if [[ "${1:-}" == "--uninstall" ]]; then
  echo ""
  hr
  echo -e "${BOLD}  claude-beep  —  Uninstaller${RESET}"
  hr
  echo ""
  rm -f "$BEEP_SCRIPT" "$STOP_SCRIPT" "$CONFIG_FILE"
  # Remove hooks from settings.json if it exists
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
                            if not any("claude-done-beep" in str(c) or "claude-stop-beep" in str(c)
                                       for c in [h.get("command","")])]
            if not hooks[event]: del hooks[event]
    if hooks: cfg["hooks"] = hooks
    elif "hooks" in cfg: del cfg["hooks"]
    with open(path, "w") as f: json.dump(cfg, f, indent=2)
    print("  Hooks removed from settings.json")
except Exception as e:
    print(f"  Could not update settings.json: {e}")
PY
  fi
  ok "claude-beep uninstalled."
  echo ""
  exit 0
fi

# ── Header ────────────────────────────────────────────────────────────
echo ""
hr
echo -e "${BOLD}  claude-beep  —  Installer${RESET}"
echo -e "  Notifies you when Claude Code finishes a task"
hr
echo ""

# ── Pre-flight checks ─────────────────────────────────────────────────
info "Checking requirements..."

[[ -d "$CLAUDE_DIR" ]] || mkdir -p "$CLAUDE_DIR"

if ! command -v python3 &>/dev/null; then
  warn "python3 not found — sound generation may be limited."
else
  ok "python3 found"
fi

if [[ "$(uname)" == "Darwin" ]]; then
  ok "macOS detected — will use system sounds"
else
  ok "Linux detected"
fi

echo ""

# ── Sound selection ───────────────────────────────────────────────────
echo -e "${BOLD}  Step 1 of 2 — Choose a notification sound${RESET}"
echo ""
echo -e "  Each sound will play a short preview as you select it."
echo ""
echo -e "  ${CYAN}1)${RESET} chime  — Two-tone ascending chime  ${YELLOW}(recommended)${RESET}"
echo -e "  ${CYAN}2)${RESET} bell   — Classic single beep"
echo -e "  ${CYAN}3)${RESET} pop    — Soft low pop"
echo -e "  ${CYAN}4)${RESET} ping   — Crisp high ping"
echo ""

# Inline preview function — plays a quick sample right in the installer
preview_sound() {
  local SOUND_TYPE="$1"
  python3 - "$SOUND_TYPE" 2>/dev/null <<'PYEOF'
import struct, wave, tempfile, os, subprocess, math, sys

sound_type = sys.argv[1] if len(sys.argv) > 1 else "chime"
rate = 44100

def sine(freq, dur, vol=0.6):
    n = int(rate * dur)
    fade = int(rate * 0.01)
    out = []
    for i in range(n):
        s = math.sin(2 * math.pi * freq * i / rate)
        if i < fade:   s *= i / fade
        elif i > n - fade: s *= (n - i) / fade
        out.append(int(32767 * vol * s))
    return out

def to_bytes(samples):
    return b"".join(struct.pack("<h", max(-32767, min(32767, s))) for s in samples)

sounds = {
    "chime": sine(523, 0.18) + sine(659, 0.28),
    "bell":  sine(440, 0.25, 0.8),
    "pop":   sine(220, 0.12, 0.5) + sine(180, 0.08, 0.3),
    "ping":  sine(880, 0.15, 0.5) + sine(1047, 0.2, 0.4),
}
samples = sounds.get(sound_type, sounds["chime"])
with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
    path = f.name
    with wave.open(f, "w") as wf:
        wf.setnchannels(1); wf.setsampwidth(2)
        wf.setframerate(rate); wf.writeframes(to_bytes(samples))
for cmd in [["paplay",path],["aplay","-q",path],["pw-play",path],
            ["afplay",path],["ffplay","-nodisp","-autoexit","-loglevel","quiet",path]]:
    try:
        if subprocess.run(cmd, capture_output=True, timeout=5).returncode == 0: break
    except: continue
os.unlink(path)
PYEOF
}

CHOSEN_SOUND=""
while true; do
  read -rp "  Enter number [1-4] (previews the sound): " SOUND_CHOICE
  case "$SOUND_CHOICE" in
    1) CHOSEN_SOUND="chime" ;;
    2) CHOSEN_SOUND="bell"  ;;
    3) CHOSEN_SOUND="pop"   ;;
    4) CHOSEN_SOUND="ping"  ;;
    *) warn "Please enter 1, 2, 3, or 4."; continue ;;
  esac
  info "Playing preview: $CHOSEN_SOUND ..."
  preview_sound "$CHOSEN_SOUND"
  echo ""
  read -rp "  Keep this sound? [Y/n]: " CONFIRM
  CONFIRM="${CONFIRM:-Y}"
  if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    ok "Sound selected: $CHOSEN_SOUND"
    break
  fi
  echo ""
done

echo ""

# ── Repeat mode ───────────────────────────────────────────────────────
echo -e "${BOLD}  Step 2 of 2 — Repeat notification${RESET}"
echo ""
echo -e "  When enabled, the sound repeats every few seconds"
echo -e "  until you type your next message in Claude Code."
echo ""

CHOSEN_REPEAT=""
read -rp "  Enable repeat notifications? [Y/n]: " REPEAT_CHOICE
REPEAT_CHOICE="${REPEAT_CHOICE:-Y}"
if [[ "$REPEAT_CHOICE" =~ ^[Yy]$ ]]; then
  CHOSEN_REPEAT="on"
  echo ""
  read -rp "  Repeat every how many seconds? [default: 5]: " INTERVAL_CHOICE
  CHOSEN_INTERVAL="${INTERVAL_CHOICE:-5}"
  # Validate it's a number
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

# ── Download & install scripts ────────────────────────────────────────
hr
info "Installing scripts to $CLAUDE_DIR ..."
echo ""

# Download or embed the beep script
# When published to GitHub, these curl lines pull from the repo.
# For local/dev use we embed them directly below.

curl -fsSL "$REPO_RAW/bin/claude-done-beep.sh" -o "$BEEP_SCRIPT" 2>/dev/null || \
  install_embedded_beep_script

curl -fsSL "$REPO_RAW/bin/claude-stop-beep.sh" -o "$STOP_SCRIPT" 2>/dev/null || \
  install_embedded_stop_script

chmod +x "$BEEP_SCRIPT" "$STOP_SCRIPT"
ok "Scripts installed"

# ── Write config ──────────────────────────────────────────────────────
cat > "$CONFIG_FILE" <<CONF
# claude-beep — Configuration
# Re-run the installer or edit this file to change settings.
# Or use flags:  bash ~/.claude/claude-done-beep.sh --help

BEEP_SOUND="$CHOSEN_SOUND"
BEEP_CUSTOM_FILE=""
BEEP_REPEAT="$CHOSEN_REPEAT"
BEEP_INTERVAL="$CHOSEN_INTERVAL"
CONF
ok "Config written → $CONFIG_FILE"

# ── Inject hooks into settings.json ──────────────────────────────────
inject_hooks() {
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
    ok "Created $SETTINGS_FILE with hooks"
    return
  fi

  # Merge into existing settings.json via Python
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

def clean_beep_hooks(lst):
    return [h for h in lst if "claude-done-beep" not in str(h) and "claude-stop-beep" not in str(h)]

stop_hooks = clean_beep_hooks(hooks.get("Stop", []))
stop_hooks.append({
    "matcher": "",
    "hooks": [{"type": "command", "command": "bash ~/.claude/claude-done-beep.sh"}]
})
hooks["Stop"] = stop_hooks

pre_hooks = clean_beep_hooks(hooks.get("PreToolUse", []))
pre_hooks.append({
    "matcher": "",
    "hooks": [{"type": "command", "command": "bash ~/.claude/claude-stop-beep.sh"}]
})
hooks["PreToolUse"] = pre_hooks

with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
print(f"  Hooks merged into {path}")
PY
  ok "Hooks injected into $SETTINGS_FILE"
}

inject_hooks

# ── Done ──────────────────────────────────────────────────────────────
echo ""
hr
echo -e "${GREEN}${BOLD}  claude-beep installed successfully!${RESET}"
hr
echo ""
echo -e "  Sound    : ${BOLD}$CHOSEN_SOUND${RESET}"
echo -e "  Repeat   : ${BOLD}$CHOSEN_REPEAT${RESET}$( [[ "$CHOSEN_REPEAT" == "on" ]] && echo "  (every ${CHOSEN_INTERVAL}s)" )"
echo ""
echo -e "${BOLD}  Useful commands:${RESET}"
echo -e "  ${CYAN}bash ~/.claude/claude-done-beep.sh --status${RESET}       show config"
echo -e "  ${CYAN}bash ~/.claude/claude-done-beep.sh --sound ping${RESET}   change sound"
echo -e "  ${CYAN}bash ~/.claude/claude-done-beep.sh --repeat off${RESET}   disable repeat"
echo -e "  ${CYAN}bash ~/.claude/claude-done-beep.sh --interval 10${RESET}  change interval"
echo ""
echo -e "  To uninstall:"
echo -e "  ${CYAN}curl -fsSL $REPO_RAW/install.sh | bash -s -- --uninstall${RESET}"
echo ""
