#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║        claude-beep  —  Task Done Notifier  v2.0             ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   --sound  bell|chime|pop|ping         Change sound
#   --sound  custom /path/to/file.wav    Use your own file
#   --repeat on|off                      Toggle repeat mode
#   --interval <seconds>                 Set repeat interval
#   --status                             Show current config
#   --help                               Show this help

CONFIG_FILE="$HOME/.claude/beep-config.sh"
PID_FILE="$HOME/.claude/beep-repeat.pid"

write_default_config() {
  cat > "$CONFIG_FILE" <<'DEFAULTS'
# claude-beep — Configuration
BEEP_SOUND="chime"
BEEP_CUSTOM_FILE=""
BEEP_REPEAT="on"
BEEP_INTERVAL="5"
DEFAULTS
}

[[ -f "$CONFIG_FILE" ]] || write_default_config
# shellcheck source=/dev/null
source "$CONFIG_FILE"

# ── Argument Parsing ─────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sound)
      if [[ "$2" == "custom" ]]; then
        sed -i.bak "s|^BEEP_SOUND=.*|BEEP_SOUND=\"custom\"|"          "$CONFIG_FILE"
        sed -i.bak "s|^BEEP_CUSTOM_FILE=.*|BEEP_CUSTOM_FILE=\"$3\"|"  "$CONFIG_FILE"
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
    --status)
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "  claude-beep — Config"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "  Sound    : $BEEP_SOUND"
      [[ "$BEEP_SOUND" == "custom" ]] && echo "  File     : $BEEP_CUSTOM_FILE"
      echo "  Repeat   : $BEEP_REPEAT"
      echo "  Interval : ${BEEP_INTERVAL}s"
      if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "  Loop     : running (PID $(cat "$PID_FILE"))"
      else
        echo "  Loop     : not running"
      fi
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      echo "  bash ~/.claude/claude-done-beep.sh --sound  bell|chime|pop|ping"
      echo "  bash ~/.claude/claude-done-beep.sh --repeat on|off"
      echo "  bash ~/.claude/claude-done-beep.sh --interval <seconds>"
      echo ""
      exit 0 ;;
    --help|-h)
      echo ""
      echo "  claude-beep — usage:"
      echo "  --sound  bell|chime|pop|ping   Change notification sound"
      echo "  --sound  custom <path>         Use a custom .wav/.ogg file"
      echo "  --repeat on|off               Toggle repeat beeping"
      echo "  --interval <seconds>          Set repeat interval (default: 5)"
      echo "  --status                      Show current settings"
      echo ""
      exit 0 ;;
    *) shift ;;
  esac
  shift
done

# ── Python Sound Generator ───────────────────────────────────────
play_via_python() {
  python3 - "$1" <<'PYEOF'
import struct, wave, tempfile, os, subprocess, math, sys

sound_type = sys.argv[1] if len(sys.argv) > 1 else "chime"
rate = 44100

def sine(freq, dur, vol=0.6):
    n = int(rate * dur)
    fade = int(rate * 0.01)
    out = []
    for i in range(n):
        s = math.sin(2 * math.pi * freq * i / rate)
        if i < fade:        s *= i / fade
        elif i > n - fade:  s *= (n - i) / fade
        out.append(int(32767 * vol * s))
    return out

def to_bytes(s):
    return b"".join(struct.pack("<h", max(-32767, min(32767, v))) for v in s)

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
            ["ffplay","-nodisp","-autoexit","-loglevel","quiet",path]]:
    try:
        if subprocess.run(cmd, capture_output=True, timeout=5).returncode == 0: break
    except: continue

os.unlink(path)
PYEOF
}

# ── Play Sound ───────────────────────────────────────────────────
play_sound() {
  if [[ "$BEEP_SOUND" == "custom" && -f "$BEEP_CUSTOM_FILE" ]]; then
    for player in afplay paplay pw-play; do
      command -v "$player" &>/dev/null && "$player" "$BEEP_CUSTOM_FILE" 2>/dev/null && return
    done
    command -v aplay &>/dev/null && aplay -q "$BEEP_CUSTOM_FILE" 2>/dev/null && return
  fi

  if [[ "$(uname)" == "Darwin" ]]; then
    declare -A M=([chime]="Glass" [bell]="Ping" [pop]="Pop" [ping]="Tink")
    afplay "/System/Library/Sounds/${M[$BEEP_SOUND]:-Glass}.aiff" 2>/dev/null && return
    printf '\a'; return
  fi

  command -v python3 &>/dev/null && play_via_python "$BEEP_SOUND" && return

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
  [[ -f "$PID_FILE" ]] && kill "$(cat "$PID_FILE")" 2>/dev/null && rm -f "$PID_FILE"
}

start_repeat_loop() {
  stop_repeat
  (
    echo $$ > "$PID_FILE"
    while true; do
      sleep "$BEEP_INTERVAL"
      source "$CONFIG_FILE" 2>/dev/null
      [[ "$BEEP_REPEAT" != "on" ]] && break
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
