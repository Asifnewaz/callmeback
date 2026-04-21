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

RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m';     RESET='\033[0m'

ok()   { echo -e "${GREEN}  ✔  $*${RESET}"; }
info() { echo -e "${CYAN}  →  $*${RESET}"; }
warn() { echo -e "${YELLOW}  ⚠  $*${RESET}"; }
err()  { echo -e "${RED}  ✘  $*${RESET}"; exit 1; }
hr()   { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

# Read from /dev/tty so curl-pipe works
ask() {
  local __var=$1 __prompt=$2 __val
  printf "%s" "$__prompt" >&2
  read -r __val </dev/tty
  printf -v "$__var" '%s' "$__val"
}

CLAUDE_DIR="$HOME/.claude"
BEEP_SCRIPT="$CLAUDE_DIR/claude-done-beep.sh"
STOP_SCRIPT="$CLAUDE_DIR/claude-stop-beep.sh"
ENGINE="$CLAUDE_DIR/sound_engine.py"
CONFIG_FILE="$CLAUDE_DIR/beep-config.sh"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
REPO_RAW="https://raw.githubusercontent.com/Asifnewaz/callmeback/main"

# ── Uninstall ─────────────────────────────────────────────────────────
if [[ "${1:-}" == "--uninstall" ]]; then
  echo ""; hr
  echo -e "${BOLD}  callmeback  —  Uninstaller${RESET}"; hr; echo ""
  rm -f "$BEEP_SCRIPT" "$STOP_SCRIPT" "$ENGINE" "$CONFIG_FILE"
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
command -v python3 &>/dev/null && ok "python3 found" || warn "python3 not found — sound may be limited"
[[ "$(uname)" == "Darwin" ]] && ok "macOS detected" || ok "Linux detected"
echo ""

# ── Download sound engine first so previews use the exact same sounds ─
info "Fetching sound engine..."
if curl -fsSL "$REPO_RAW/bin/sound_engine.py" -o "$ENGINE" 2>/dev/null; then
  ok "Sound engine ready"
else
  warn "Could not fetch sound engine — previews may not play"
fi
echo ""

# ── Preview function — uses the SAME engine as the installed script ───
preview_sound() {
  local name="$1"
  if command -v python3 &>/dev/null && [[ -f "$ENGINE" ]]; then
    python3 "$ENGINE" "$name" 2>/dev/null
  fi
}

# ── Step 1 — Sound selection ──────────────────────────────────────────
echo -e "${BOLD}  Step 1 of 2 — Choose a notification sound${RESET}"
echo -e "  Each number plays a live preview."
echo ""
echo -e "     ${YELLOW}— Soft & gentle —${RESET}"
echo -e "  ${CYAN}1)${RESET} gentle  — Three soft ascending tones       ${YELLOW}(recommended)${RESET}"
echo -e "  ${CYAN}2)${RESET} soft    — Barely-there low hum"
echo -e "  ${CYAN}3)${RESET} water   — Water drop with quick decay"
echo -e "  ${CYAN}4)${RESET} whoosh  — Airy rising sweep"
echo ""
echo -e "     ${YELLOW}— Classic —${RESET}"
echo -e "  ${CYAN}5)${RESET} chime   — Two-tone ascending chime"
echo -e "  ${CYAN}6)${RESET} bell    — Classic single beep"
echo -e "  ${CYAN}7)${RESET} pop     — Short low pop"
echo -e "  ${CYAN}8)${RESET} ping    — Crisp high ping"
echo ""

declare -A SOUND_MAP=([1]="gentle" [2]="soft" [3]="water" [4]="whoosh"
                      [5]="chime"  [6]="bell"  [7]="pop"   [8]="ping")
CHOSEN_SOUND=""

while true; do
  ask SOUND_CHOICE "  Enter number [1-8]: "
  echo ""
  CHOSEN_SOUND="${SOUND_MAP[$SOUND_CHOICE]:-}"
  if [[ -z "$CHOSEN_SOUND" ]]; then
    warn "Please enter a number between 1 and 8."; echo ""; continue
  fi
  info "Playing preview: $CHOSEN_SOUND ..."
  preview_sound "$CHOSEN_SOUND"
  echo ""
  ask CONFIRM "  Keep this sound? [Y/n]: "
  echo ""
  [[ "${CONFIRM:-Y}" =~ ^[Yy]$ ]] && { ok "Sound selected: $CHOSEN_SOUND"; break; }
  echo ""
done

echo ""

# ── Step 2 — Repeat mode ──────────────────────────────────────────────
echo -e "${BOLD}  Step 2 of 2 — Repeat notification${RESET}"
echo ""
echo -e "  When enabled, a softer version of the sound repeats every"
echo -e "  few seconds until you type your next message in Claude Code."
echo ""

ask REPEAT_CHOICE "  Enable repeat notifications? [Y/n]: "
echo ""

if [[ "${REPEAT_CHOICE:-Y}" =~ ^[Yy]$ ]]; then
  CHOSEN_REPEAT="on"
  ask INTERVAL_CHOICE "  Repeat every how many seconds? [default: 5]: "
  echo ""
  CHOSEN_INTERVAL="${INTERVAL_CHOICE:-5}"
  [[ "$CHOSEN_INTERVAL" =~ ^[0-9]+$ ]] || { warn "Invalid, defaulting to 5s."; CHOSEN_INTERVAL="5"; }
  ask LIMIT_CHOICE "  Max number of repeat beeps? [default: 3]: "
  echo ""
  CHOSEN_LIMIT="${LIMIT_CHOICE:-3}"
  [[ "$CHOSEN_LIMIT" =~ ^[0-9]+$ ]] || { warn "Invalid, defaulting to 3."; CHOSEN_LIMIT="3"; }
  ok "Repeat: every ${CHOSEN_INTERVAL}s, max ${CHOSEN_LIMIT} times"
else
  CHOSEN_REPEAT="off"
  CHOSEN_INTERVAL="5"
  CHOSEN_LIMIT="3"
  ok "Repeat: disabled"
fi

echo ""

# ── Download scripts ──────────────────────────────────────────────────
hr
info "Installing to $CLAUDE_DIR ..."
echo ""

curl -fsSL "$REPO_RAW/bin/claude-done-beep.sh" -o "$BEEP_SCRIPT" \
  || err "Failed to download claude-done-beep.sh"
curl -fsSL "$REPO_RAW/bin/claude-stop-beep.sh" -o "$STOP_SCRIPT" \
  || err "Failed to download claude-stop-beep.sh"

chmod +x "$BEEP_SCRIPT" "$STOP_SCRIPT"
ok "Scripts installed"

# ── Write config ──────────────────────────────────────────────────────
cat > "$CONFIG_FILE" <<CONF
# callmeback — Configuration
BEEP_SOUND="$CHOSEN_SOUND"
BEEP_CUSTOM_FILE=""
BEEP_REPEAT="$CHOSEN_REPEAT"
BEEP_INTERVAL="$CHOSEN_INTERVAL"
BEEP_LIMIT="$CHOSEN_LIMIT"
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
echo -e "  Repeat   : ${BOLD}$CHOSEN_REPEAT${RESET}$( [[ "$CHOSEN_REPEAT" == "on" ]] && echo " (every ${CHOSEN_INTERVAL}s, max ${CHOSEN_LIMIT}x)" )"
echo ""
echo -e "${BOLD}  Commands:${RESET}"
echo -e "  ${CYAN}bash ~/.claude/claude-done-beep.sh --status${RESET}"
echo -e "  ${CYAN}bash ~/.claude/claude-done-beep.sh --sound gentle${RESET}"
echo -e "  ${CYAN}bash ~/.claude/claude-done-beep.sh --repeat off${RESET}"
echo -e "  ${CYAN}bash ~/.claude/claude-done-beep.sh --limit 3${RESET}"
echo -e "  ${CYAN}bash ~/.claude/claude-done-beep.sh --interval 5${RESET}"
echo ""
echo -e "  Uninstall:"
echo -e "  ${CYAN}curl -fsSL $REPO_RAW/install.sh | bash -s -- --uninstall${RESET}"
echo ""
