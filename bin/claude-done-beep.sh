#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║        callmeback  —  Task Done Notifier  v2.2              ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Sounds: chime | bell | pop | ping | soft | water | whoosh | gentle
#
# Usage:
#   --sound  <name>               Change sound
#   --sound  custom /path/file    Use your own file
#   --repeat on|off               Toggle repeat mode
#   --limit  <n>                  Max repeat beeps (default: 3)
#   --interval <seconds>          Seconds between repeats
#   --status                      Show current config
#   --help                        Show this help

CONFIG_FILE="$HOME/.claude/beep-config.sh"
PID_FILE="$HOME/.claude/beep-repeat.pid"

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

# Migrate old configs that don't have BEEP_LIMIT yet
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

# ── Python Sound Generator ───────────────────────────────────────
# BUG FIX: Write sound name to a temp file so the Python heredoc
# (which uses single quotes = no variable expansion) can read it.
play_via_python() {
  local SOUND_NAME="$1"
  local SOUND_FILE
  SOUND_FILE=$(mktemp /tmp/cmb_sound_XXXXXX)
  echo "$SOUND_NAME" > "$SOUND_FILE"

  python3 - "$SOUND_FILE" <<'PYEOF'
import struct, wave, tempfile, os, subprocess, math, sys

# Read sound name from the temp file passed as argument
sound_file = sys.argv[1] if len(sys.argv) > 1 else ""
sound_type = "gentle"
if sound_file and os.path.exists(sound_file):
    with open(sound_file) as f:
        sound_type = f.read().strip()
    os.unlink(sound_file)

rate = 44100

def sine(freq, dur, vol=0.6):
    n, fade = int(rate * dur), int(rate * 0.015)
    out = []
    for i in range(n):
        s = math.sin(2 * math.pi * freq * i / rate)
        if i < fade:       s *= i / fade
        elif i > n - fade: s *= (n - i) / fade
        out.append(int(32767 * vol * s))
    return out

def sine_exp(freq, dur, vol=0.6, decay=6.0):
    n = int(rate * dur)
    return [int(32767 * vol * math.exp(-decay * i / n) *
                math.sin(2 * math.pi * freq * i / rate)) for i in range(n)]

def silence(dur):
    return [0] * int(rate * dur)

sounds = {
    "chime":  sine(523, 0.18) + sine(659, 0.28),
    "bell":   sine(440, 0.25, 0.8),
    "pop":    sine(220, 0.12, 0.5) + sine(180, 0.08, 0.3),
    "ping":   sine(880, 0.15, 0.5) + sine(1047, 0.2, 0.4),
    "soft":   sine(330, 0.20, 0.28) + sine(392, 0.25, 0.18),
    "water":  sine_exp(1200, 0.35, 0.55, 7.0) + silence(0.04) + sine_exp(900, 0.28, 0.3, 9.0),
    "whoosh": [
        int(32767 * 0.3 *
            math.sin(2 * math.pi * (300 + 400 * (i / int(rate * 0.4))) * i / rate) *
            math.exp(-3.5 * i / int(rate * 0.4)))
        for i in range(int(rate * 0.4))
    ],
    "gentle": (sine_exp(528, 0.30, 0.35, 5.0) + silence(0.06) +
               sine_exp(660, 0.30, 0.28, 5.5) + silence(0.06) +
               sine_exp(792, 0.35, 0.22, 6.0)),
}

samples = sounds.get(sound_type, sounds["gentle"])

def to_bytes(s):
    return b"".join(struct.pack("<h", max(-32767, min(32767, v))) for v in s)

with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
    path = f.name
    with wave.open(f, "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(rate)
        wf.writeframes(to_bytes(samples))

played = False
for cmd in [
    ["afplay", path],
    ["paplay", path],
    ["aplay", "-q", path],
    ["pw-play", path],
    ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", path],
]:
    try:
        if subprocess.run(cmd, capture_output=True, timeout=5).returncode == 0:
            played = True
            break
    except:
        continue

os.unlink(path)
sys.exit(0 if played else 1)
PYEOF
}

# ── Play Sound ───────────────────────────────────────────────────
play_sound() {
  # Custom file
  if [[ "$BEEP_SOUND" == "custom" && -f "$BEEP_CUSTOM_FILE" ]]; then
    for player in afplay paplay pw-play; do
      command -v "$player" &>/dev/null && "$player" "$BEEP_CUSTOM_FILE" 2>/dev/null && return
    done
    command -v aplay &>/dev/null && aplay -q "$BEEP_CUSTOM_FILE" 2>/dev/null && return
  fi

  # macOS system sounds for classic presets — Python for soft ones
  if [[ "$(uname)" == "Darwin" ]]; then
    declare -A MAC_MAP=([chime]="Glass" [bell]="Ping" [pop]="Pop" [ping]="Tink")
    if [[ -n "${MAC_MAP[$BEEP_SOUND]:-}" ]]; then
      afplay "/System/Library/Sounds/${MAC_MAP[$BEEP_SOUND]}.aiff" 2>/dev/null && return
    fi
    # soft/water/whoosh/gentle fall through to Python below
  fi

  # Python generator — works on macOS + Linux, carries the selected sound name correctly
  if command -v python3 &>/dev/null; then
    play_via_python "$BEEP_SOUND" && return
  fi

  # Last resort: system sound files on Linux
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
  # BUG FIX: split into two separate steps so rm always runs
  # regardless of whether kill succeeded
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
    # BUG FIX: save the subshell PID, not the parent $$
    echo $BASHPID > "$PID_FILE"

    local count=0

    while true; do
      sleep "$BEEP_INTERVAL"

      # Re-read config — picks up live changes to repeat/limit/interval
      source "$CONFIG_FILE" 2>/dev/null

      # Stop if repeat was toggled off
      [[ "$BEEP_REPEAT" != "on" ]] && break

      # Stop if we've hit the beep limit
      count=$(( count + 1 ))
      [[ "$count" -gt "$BEEP_LIMIT" ]] && break

      play_sound
    done

    rm -f "$PID_FILE"
  ) &
  disown
}

# ── Main ─────────────────────────────────────────────────────────
stop_repeat
play_sound
[[ "$BEEP_REPEAT" == "on" ]] && start_repeat_loop
