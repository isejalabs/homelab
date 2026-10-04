---
status: current
---

# Proxmox VM Power Lifecycle

## Overview

[#1431](https://github.com/isejalabs/homelab/issues/1431): a `just proxmox::vm::*` recipe set that lists, starts, stops, gracefully shuts down, or hard-resets Proxmox VMs, via the Proxmox REST API -- no SSH to individual Proxmox nodes, no hand-picking `70081<env-id><n>` VM IDs. Sibling to `proxmox::snapshot::*` ([#1296](https://github.com/isejalabs/homelab/issues/1296), see [`docs/proxmox-vm-snapshots.md`](proxmox-vm-snapshots.md)), which covers snapshotting/rollback instead of power lifecycle -- both share the same credential/discovery mechanism, described there in full and only summarized here.

```sh
just proxmox::vm::list -e dev                        # read-only: VMs, no snapshot detail
just proxmox::vm::start -e dev                        # every VM in the environment; never prompts
just proxmox::vm::start -e dev --vmid 7008130         # just one VM
just proxmox::vm::shutdown -e dev                     # every VM; destructive -- see below
just proxmox::vm::stop -e dev --vmid 7008130          # one VM; no prompt, blast radius is explicit
just proxmox::vm::reset -e dev
```

`snapshot` and `vm` are kept as sibling submodules under `proxmox` rather than nesting one inside the other (e.g. `proxmox::vm::snapshot::*`) -- revisit only if a third sibling submodule would otherwise collide with a snapshot concept.

## Credential reuse and VM discovery

Identical mechanism to `proxmox::snapshot::*` -- see [`docs/proxmox-vm-snapshots.md`](proxmox-vm-snapshots.md#credential-reuse) and [...#vm-discovery](proxmox-vm-snapshots.md#vm-discovery). The same Proxmox API token is reused (`VM.PowerMgmt` was already an implied/anticipated privilege on it before this feature existed, since `snapshot::rollback` already stops and starts VMs internally as part of its own rollback sequence).

## Environment-wide vs. single-VM targeting

Every `vm::*` recipe accepts `-e/--environment` (required, matching `snapshot::*`'s "every VM in the environment, in one go" convention) and an optional `--vmid` that narrows the action to just that one VM (still validated against the environment's own discovered VMs -- a `--vmid` that doesn't belong to `-e`'s environment is rejected, not silently ignored).

## Destructive actions are gated -- but only environment-wide

`stop` (hard power-off), `shutdown` (graceful, ACPI-signaled power-off), and `reset` (hard reboot) require typing the environment name to confirm (or `--yes` to skip that, e.g. non-interactive use) **only when acting on the whole environment** (no `--vmid` given) -- same UX as `snapshot::rollback`. A single `--vmid` target skips the prompt: naming exactly one VM in the command already makes the blast radius explicit, unlike an environment-wide invocation which could silently affect VMs the operator forgot were even part of that environment. `start` never prompts, at any scope -- starting a VM has no destructive potential.

## What each command does

- **`list`** (`scripts/proxmox-vm-list.sh`) -- discovers the environment's VMs (`VMID`/`NAME`/`NODE`/ `STATUS`). Read-only, no per-VM snapshot API calls -- see [`docs/proxmox-vm-snapshots.md`](proxmox-vm-snapshots.md) for the sibling `proxmox::snapshot::list`, which additionally lists each VM's snapshots.
- **`start`/`shutdown`/`stop`/`reset`** (`scripts/proxmox-vm-power.sh --action <verb>`, one shared script parameterized by action rather than four near-duplicate files) -- resolves the selected VM(s) (all of `-e`'s environment, or just `--vmid`), gates on confirmation per the rule above, then calls `POST /nodes/<node>/qemu/<vmid>/status/<action>` for each **in parallel** (no cross-VM ordering dependency, unlike `snapshot::rollback`'s per-VM stop-then-rollback-then-start sequence within a single VM), waiting for each resulting Proxmox task to complete.

## Known follow-ups (not yet implemented)

- No `reboot` (graceful restart) action -- only `reset` (hard). Proxmox exposes both; add `reboot` the same way if a real need for it comes up.
