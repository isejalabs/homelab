---
description: Mink context management — automatic via hooks
---

This project uses [Mink](https://github.com/drewpayment/mink) for cross-session context management.

## How it works

- Mink runs automatically through the Claude Code hooks configured in `.claude/settings.json` (`SessionStart`, `PreToolUse`, `PostToolUse`, and `Stop`).
- Mink state lives in `~/.mink/` on the user's machine, not in this repository. Do not create or write an in-repository Mink state directory.
- Mink supplements the existing OpenWolf hooks; do not remove or alter the `.wolf/` state or hooks as part of Mink work.
- Read intelligence, write enforcement, bug memory, and the token ledger are handled by the hooks. Do not manually read or update Mink state files.

## When to act on Mink

- If a user asks to save a note, remember something, or log something to the Mink wiki, use the `mink-note` skill when it is installed.
- If Mink surfaces a learning, past bug, or repeat-read warning, treat it as project memory and follow it.
- `mink dashboard` and `mink agent` are user tools; do not invoke them on the user's behalf.
