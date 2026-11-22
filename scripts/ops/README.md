# Operational scripts

The scripts behind the day-to-day `just` recipes, one folder per domain, each with the `just` module that wraps it as `mod.just`. The root [`.justfile`](../../.justfile) loads `backup`, `k8s` and `proxmox` from here; each parent module loads the domain modules below it, so the recipe name mirrors the nesting (`just backup::kopiur::list`, `just proxmox::vm::start`). `just --list --list-submodules` shows the whole tree. The recipes pass their flags straight to the scripts, which can also be run directly.

| Domain | Recipes | Scripts |
| --- | --- | --- |
| [`kopiur/`](kopiur/README.md) | `just backup::kopiur::<recipe>` | kopiur backup, restore and PVC migration |
| [`longhorn/`](longhorn/README.md) | `just backup::longhorn-snapshot::<recipe>` | Longhorn's local volume snapshots |
| [`keycloak/`](keycloak/README.md) | `just backup::keycloak::<recipe>` | Keycloak database restore |
| [`immich/`](immich/README.md) | `just backup::immich::<recipe>` | Immich database restore |
| [`k8s/`](k8s/README.md) | `just k8s::pods::<recipe>` | Kubernetes pod inspection (jq filters on `kubectl`, no scripts) |
| [`proxmox/`](proxmox/README.md) | `just proxmox::snapshot::<recipe>`, `just proxmox::vm::<recipe>` | Proxmox VM snapshots and power lifecycle |

| Module | Role |
| --- | --- |
| [`backup.just`](backup.just) | parent of the `kopiur`, `longhorn-snapshot`, `keycloak` and `immich` modules (the folders `kopiur/`, `longhorn/`, `keycloak/` and `immich/`) — `just backup::<module>::<recipe>` |

Adding a domain: create `ops/<domain>/` with a `mod.just`, its scripts and a `README.md` (see [`kopiur/README.md`](kopiur/README.md) for the shape), load the module from [`backup.just`](backup.just) or from the root [`.justfile`](../../.justfile), and link the folder in the table above. A script under `ops/<domain>/` sets `SCRIPTS_DIR` with two `..` (see [`lib/common.sh`](../lib/common.sh)).
