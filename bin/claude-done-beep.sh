#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║        callmeback  —  Task Done Notifier  v2.3              ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Sounds: chime | bell | pop | ping | soft | water | whoosh | gentle
#
# Usage:
#   --sound    <name>             Change sound
#   --sound    custom /path/file  Use your own file
#   --repeat   on|off             Toggle repeat mode
#   --limit    <n>                Max repeat beeps (default: 3)
#   --interval <seconds>          Seconds between repeats (default: 5)
#   --status                      Show current config
#   --help                        Show this help

CONFIG_FILE="$HOME/.claude/beep-config.sh"
PID_FILE="$HOME/.claude/beep-repeat.pid"
ENGINE="$HOME/.claude/sound_engine.py"

write_default_config() {
  cat > "$CONFIG_FILE" <<'DEFAULTS'
# callmeback — Configuration
BEEP_SOUND="gentle"
BEEP_CUSTOM_FILE=""
BEEP_REPEAT="on"
BEEP_INTERVAL="5"
BEEP_LIMIT="3"
DEFAULTS
}

[[ -f "$CONFIG_FILE" ]] || write_default_config
grep -q "^BEEP_LIMIT=" "$CONFIG_FILE" || echo 'BEEP_LIMIT="3"' >> "$CONFIG_FILE"

# shellcheck source=/dev/null
source "$CONFIG_FILE"

# ── Argument Parsing ─────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sound)
      if [[ "$2" == "custom" ]]; then
        sed -i.bak "s|^BEEP_SOUND=.*|BEEP_SOUND=\"custom\"|"         "$CONFIG_FILE"
        sed -i.bak "s|^BEEP_CUSTOM_FILE=.*|BEEP_CUSTOM_FILE=\"$3\"|" "$CONFIG_FILE"
        echo "Sound set to: custom ($3)"; exit 0
      else
        sed -i.bak "s|^BEEP_SOUND=.*|BEEP_SOUND=\"$2\"|" "$CONFIG_FILE"
        echo "Sound set to: $2"; exit 0
      fi ;;
    --repeat)
      sed -i.bak "s|^BEEP_REPEAT=.*|BEEP_REPEAT=\"$2\"|" "$CONFIG_FILE"
      echo "Repeat: $2"; exit 0 ;;
    --interval)
      sed -i.bak "s|^BEEP_INTERVAL=.*|BEEP_INTERVAL=\"$2\"|" "$CONFIG_FILE"
      echo "Interval: ${2}s"; exit 0 ;;
    --limit)
      sed -i.bak "s|^BEEP_LIMIT=.*|BEEP_LIMIT=\"$2\"|" "$CONFIG_FILE"
      echo "Beep limit: $2"; exit 0 ;;
    --status)
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "  callmeback — Config"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "  Sound    : $BEEP_SOUND"
      [[ "$BEEP_SOUND" == "custom" ]] && echo "  File     : $BEEP_CUSTOM_FILE"
      echo "  Repeat   : $BEEP_REPEAT"
      echo "  Limit    : ${BEEP_LIMIT}x"
      echo "  Interval : ${BEEP_INTERVAL}s"
      if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "  Loop     : running (PID $(cat "$PID_FILE"))"
      else
        echo "  Loop     : not running"
      fi
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      echo "  Sounds: chime | bell | pop | ping | soft | water | whoosh | gentle"
      echo ""
      echo "  bash ~/.claude/claude-done-beep.sh --sound gentle"
      echo "  bash ~/.claude/claude-done-beep.sh --repeat on|off"
      echo "  bash ~/.claude/claude-done-beep.sh --limit 3"
      echo "  bash ~/.claude/claude-done-beep.sh --interval 5"
      echo ""
      exit 0 ;;
    --help|-h)
      echo ""
      echo "  callmeback — usage:"
      echo "  --sound    chime|bell|pop|ping|soft|water|whoosh|gentle"
      echo "  --sound    custom <path>   Use a custom .wav/.ogg file"
      echo "  --repeat   on|off          Toggle repeat beeping"
      echo "  --limit    <n>             Max times to repeat (default: 3)"
      echo "  --interval <seconds>       Seconds between repeats (default: 5)"
      echo "  --status                   Show current settings"
      echo ""
      exit 0 ;;
    *) shift ;;
  esac
  shift
done

# ── Play Sound ───────────────────────────────────────────────────
# mode: "alert" (full, task done) or "reminder" (softer, repeat beep)
play_sound() {
  local mode="${1:-alert}"

  # Custom file — only for alert, reminder always uses engine
  if [[ "$BEEP_SOUND" == "custom" && "$mode" == "alert" && -f "$BEEP_CUSTOM_FILE" ]]; then
    for player in afplay paplay pw-play; do
      command -v "$player" &>/dev/null && "$player" "$BEEP_CUSTOM_FILE" 2>/dev/null && return
    done
    command -v aplay &>/dev/null && aplay -q "$BEEP_CUSTOM_FILE" 2>/dev/null && return
  fi

  # Use the shared sound engine (guarantees same sound as installer preview)
  if command -v python3 &>/dev/null && [[ -f "$ENGINE" ]]; then
    if [[ "$mode" == "reminder" ]]; then
      python3 "$ENGINE" "$BEEP_SOUND" reminder && return
    else
      python3 "$ENGINE" "$BEEP_SOUND" && return
    fi
  fi

  # macOS fallback if engine is missing (bash 3.2 compatible, no associative arrays)
  if [[ "$(uname)" == "Darwin" ]]; then
    local snd
    case "$BEEP_SOUND" in
      chime) snd="Glass" ;; bell) snd="Ping" ;;
      pop)   snd="Pop"   ;; ping) snd="Tink" ;;
      *)     snd="Glass" ;;
    esac
    afplay "/System/Library/Sounds/${snd}.aiff" 2>/dev/null && return
  fi

  # Linux fallback
  if command -v paplay &>/dev/null; then
    for f in /usr/share/sounds/freedesktop/stereo/complete.oga \
              /usr/share/sounds/freedesktop/stereo/bell.oga; do
      [[ -f "$f" ]] && paplay "$f" 2>/dev/null && return
    done
  fi

  printf '\a'
}

# ── Repeat Loop ──────────────────────────────────────────────────
stop_repeat() {
  if [[ -f "$PID_FILE" ]]; then
    local OLD_PID
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
    [[ -n "$OLD_PID" ]] && kill "$OLD_PID" 2>/dev/null
    rm -f "$PID_FILE"
  fi
}

start_repeat_loop() {
  stop_repeat
  (
    echo $BASHPID > "$PID_FILE"
    local count=0
    while true; do
      sleep "$BEEP_INTERVAL"
      source "$CONFIG_FILE" 2>/dev/null
      [[ "$BEEP_REPEAT" != "on" ]] && break
      count=$(( count + 1 ))
      [[ "$count" -gt "$BEEP_LIMIT" ]] && break
      # Reminder beep — same sound, noticeably softer/shorter
      play_sound reminder
    done
    rm -f "$PID_FILE"
  ) &
  disown
}

# ── Main ─────────────────────────────────────────────────────────
stop_repeat
play_sound alert
[[ "$BEEP_REPEAT" == "on" ]] && start_repeat_loop
