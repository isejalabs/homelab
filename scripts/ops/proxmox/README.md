# Proxmox VM snapshot and power management

Wrapped by `just proxmox::snapshot::<create|list|rollback|delete>` and `just proxmox::vm::<list|start|stop|shutdown|reset>` — see [`docs/operations/proxmox-vm-snapshots.md`](../../../docs/operations/proxmox-vm-snapshots.md) and [`docs/operations/proxmox-vm-power.md`](../../../docs/operations/proxmox-vm-power.md) for the day-to-day operational guides. Each script documents its purpose and usage in a header comment; this README is an index, not a duplicate of that.

| Script | Purpose |
| --- | --- |
| [`mod.just`](mod.just) | parent of the `snapshot` and `vm` modules — `just proxmox::<module>::<recipe>` |
| [`snapshot.just`](snapshot.just) | the `just` recipes `create`, `list`, `delete` and `rollback` |
| [`vm.just`](vm.just) | the `just` recipes `list`, `start`, `shutdown`, `stop` and `reset` |
| [`snapshot-list.sh`](snapshot-list.sh) | lists an environment's VMs and each VM's snapshots |
| [`snapshot-create.sh`](snapshot-create.sh) | creates a named snapshot on every VM in an environment |
| [`snapshot-delete.sh`](snapshot-delete.sh) | deletes a named snapshot from every VM that has it (or just `--vmid`) |
| [`snapshot-rollback.sh`](snapshot-rollback.sh) | rolls every VM in an environment back to a named snapshot and restarts them |
| [`vm-list.sh`](vm-list.sh) | lists an environment's VMs (no snapshot detail — see `snapshot-list.sh` for that) |
| [`vm-power.sh`](vm-power.sh) | one shared script for `start`/`stop`/`shutdown`/`reset`, parameterized by `--action` |

All six source [`lib/proxmox.sh`](../../lib/proxmox.sh) (Proxmox API auth, VM discovery, task polling) in addition to [`lib/common.sh`](../../lib/common.sh).
