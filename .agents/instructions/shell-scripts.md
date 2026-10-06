# Conventions for scripts under `scripts/`

Follow these whenever creating or editing a script under `scripts/` — not just when explicitly asked to document one. Both rules below already exist in practice across `scripts/lib/common.sh` and `scripts/lib/proxmox.sh` (every function there has a comment); this makes that practice explicit and extends it to every script's own local helper functions too, where it's been applied inconsistently.

## Every function gets a comment immediately above it

A short comment describing what the function does and any non-obvious behavior or parameter, immediately above the function definition (no blank line between them) — the same shape as `scripts/lib/proxmox.sh`'s `proxmox_wait_task`/`proxmox_filter_vmid`/etc. Exceptions: a function whose full behavior is genuinely self-evident from its name and body together needs nothing extra (e.g. a bare `usage()` that just echoes a usage string and exits — a comment there would only restate the code).

A comment that only explains *why* a design choice is safe (e.g. "parallel is fine here because ZFS snapshots are metadata-only") is not a substitute for saying *what* the function does, unless the *what* is already obvious from its name/call site — don't rely on a rationale-only comment to carry both jobs. This matters most for a script's own local helper functions (e.g. `rollback_one()`/`snapshot_one()`-style per-item workers), which are easy to leave undocumented since they're private to one file, unlike a shared `lib/*.sh` function another script will also need to understand cold.

## Every new script gets an entry in `scripts/README.md`

`scripts/README.md` is an index of every script under `scripts/`, grouped by purpose, each with a one-line description and a link to the script itself (see its own header comment for the header comment for the full explanation — the README is deliberately not a duplicate of that). A new script joins an existing group's table if one fits, or gets a new `##` section (table plus a short intro, matching the existing sections' shape) if it doesn't. This applies even when the script is also documented in a standalone `docs/*.md` operational guide (e.g. `docs/proxmox-vm-snapshots.md`) — that doc and this index serve different readers (someone learning the workflow vs. someone scanning `scripts/` for what exists) and neither substitutes for the other.
