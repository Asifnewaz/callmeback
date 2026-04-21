#!/bin/bash
# callmeback — Stop repeat loop when user returns to Claude Code
# Hooked to: PreToolUse (fires the moment you type a new message)

PID_FILE="$HOME/.claude/beep-repeat.pid"

# BUG FIX: always remove the PID file regardless of whether kill succeeds.
# Previous version used &&  which skipped rm if kill failed (e.g. process
# already dead), leaving a stale PID file that blocked future loops.
if [[ -f "$PID_FILE" ]]; then
  OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
  [[ -n "$OLD_PID" ]] && kill "$OLD_PID" 2>/dev/null
  rm -f "$PID_FILE"
fi
