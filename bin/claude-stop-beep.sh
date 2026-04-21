#!/bin/bash
# claude-beep — Stop repeat loop when user returns to Claude Code
# Hooked to: PreToolUse

PID_FILE="$HOME/.claude/beep-repeat.pid"
[[ -f "$PID_FILE" ]] && kill "$(cat "$PID_FILE")" 2>/dev/null && rm -f "$PID_FILE"
