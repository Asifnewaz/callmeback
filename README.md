# 🔔 claude-beep

> Plays a notification sound when **Claude Code** finishes a task — so you can switch tabs and come back when it's done.

![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)
![Shell](https://img.shields.io/badge/shell-bash-green)

---

## Features

- 🔊 **4 built-in sounds** — chime, bell, pop, ping  
- 🎵 **Custom sound** — use any `.wav` / `.ogg` / `.aiff` file  
- 🔁 **Repeat mode** — beeps every N seconds until you return to the CLI  
- 🔇 **Toggle repeat** on or off any time  
- 🖥️ Works on **macOS** and **Linux** (no extra dependencies needed)  
- ⚡ Installs in under a minute  

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Asifnewaz/claude-beep/main/install.sh | bash
```

The installer will:
1. Ask you to **choose a sound** (with a live preview)
2. Ask if you want **repeat notifications**
3. Wire everything into your `~/.claude/settings.json` automatically

---

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/Asifnewaz/claude-beep/main/install.sh | bash -s -- --uninstall
```

---

## Commands

After installation, you can change settings any time:

```bash
# Show current config
bash ~/.claude/claude-done-beep.sh --status

# Change sound
bash ~/.claude/claude-done-beep.sh --sound chime
bash ~/.claude/claude-done-beep.sh --sound bell
bash ~/.claude/claude-done-beep.sh --sound pop
bash ~/.claude/claude-done-beep.sh --sound ping

# Use your own sound file
bash ~/.claude/claude-done-beep.sh --sound custom /path/to/sound.wav

# Toggle repeat mode
bash ~/.claude/claude-done-beep.sh --repeat on
bash ~/.claude/claude-done-beep.sh --repeat off

# Change repeat interval (default: 5 seconds)
bash ~/.claude/claude-done-beep.sh --interval 10
```

---

## How it works

claude-beep uses [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks):

| Hook | Trigger | Action |
|---|---|---|
| `Stop` | Claude finishes a task | Plays sound + starts repeat loop |
| `PreToolUse` | You type your next message | Kills the repeat loop |

The repeat loop runs as a detached background process. It re-reads your config on every tick, so changes (like `--repeat off`) take effect instantly.

---

## Sounds

| Name | Description |
|---|---|
| `chime` | Two-tone ascending chime *(default)* |
| `bell` | Classic single beep |
| `pop` | Soft low pop |
| `ping` | Crisp high ping |

Sounds are generated via Python — no audio files needed. On macOS the system sound library is used instead.

---

## Config file

Settings live at `~/.claude/beep-config.sh`:

```bash
BEEP_SOUND="chime"          # bell | chime | pop | ping | custom
BEEP_CUSTOM_FILE=""         # path to custom sound file
BEEP_REPEAT="on"            # on | off
BEEP_INTERVAL="5"           # seconds between repeats
```

---

## Requirements

| Requirement | Notes |
|---|---|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Must be installed |
| `bash` | Pre-installed on macOS and Linux |
| `python3` | Pre-installed on most systems (used for sound generation on Linux) |

---

## License

MIT — use it, modify it, share it.
