Helper scripts that don't belong to a single `k8s/`/`terragrunt/` unit — CI validation entry points, bulk SOPS encrypt/decrypt, Terragrunt state cleanup, kopiur backup/restore operations, the Keycloak database restore, and Proxmox VM snapshot/power management. Each script documents its own purpose and usage in a header comment (see the linked file itself for the full explanation); this README is an index, not a duplicate of that.

Shell scripts default to `#!/bin/sh` unless a feature genuinely requires bash (e.g. arrays, `[[ ]]`, `set -o pipefail`) — most here are plain POSIX `sh`. The `kopiur-*.sh`, `longhorn-snapshot-*.sh` and `proxmox-*.sh` scripts are bash (arrays) and, unlike most others here, are also wrapped by `just` recipes rather than run directly — see [`kopiur.just`](kopiur.just) and [`proxmox-snapshot.just`](proxmox-snapshot.just)/[`proxmox-vm.just`](proxmox-vm.just).

## CI validation

Invoked by the matching `.github/workflows/*.yml` on every PR and push to `main` (see the root [`CLAUDE.md`](../CLAUDE.md)'s CI section for the full list and what each gate covers).

| Script | Checks |
| --- | --- |
| [`kustomize-build-all.sh`](kustomize-build-all.sh) | `kubectl kustomize` + kubeconform across every `k8s/` overlay, plus a `targetNamespace` ban in `flux/ks.yaml` and a check that each `keycloak-realm` Terragrunt unit's `keycloak_url` matches its Keycloak overlay's hostname |
| [`vendor-manifests.sh`](vendor-manifests.sh) | `check` fails when a manifest vendored under a unit's `vendor/` directory differs from the upstream file named in the unit's `kustomization.yaml`; `update` re-downloads them (run it after Renovate bumps the version in that URL) |
| [`terragrunt-validate-all.sh`](terragrunt-validate-all.sh) | `terragrunt init -backend=false` + `validate` across every `terragrunt/` unit (or only the given ones); `prod`/`qa` units must also have a committed provider lock file and are init'd with `-lockfile=readonly` |
| [`helmfile-template-all.sh`](helmfile-template-all.sh) | renders `k8s/bootstrap/helmfile/{crds,apps}` for every environment |
| [`flate-test-all.sh`](flate-test-all.sh) | `flate test all` against every environment's top-level Flux sync target |
| [`bootstrap-apps-ci-test.sh`](bootstrap-apps-ci-test.sh) | the bootstrap `apps` helmfile stage, against an ephemeral kind cluster |
| [`check-workloads-catalog.sh`](check-workloads-catalog.sh) | the `Apps`/`Infra` tables in `docs/architecture/workloads.md` against `k8s/{apps,infra}/*/*/flux` and the unit lists in `k8s/bootstrap/cluster/flux/sets/` (runs in the `docs-link-check` workflow; optional repo-root argument to check a copy of the tree) |
| [`check-sorting.py`](check-sorting.py) | leading-field/`metadata` key ordering (`.agents/instructions/sorting.md`) — needs [`requirements.txt`](requirements.txt) installed first |
| [`install-actionlint.sh`](install-actionlint.sh) | not a check itself — installs the pinned `actionlint` binary the `actionlint` workflow lints with |
| [`renovate-config-validator-version.sh`](renovate-config-validator-version.sh) | not a check itself — sourced to pin the `renovate-config-validator` version the `renovate-config-validate` workflow uses |

## SOPS bulk operations

Run manually, from the repo root. See [`docs/architecture/secrets.md`](../docs/architecture/secrets.md) for how SOPS fits into the repo's secrets handling.

| Script | Purpose |
| --- | --- |
| [`sops-encrypt-all.sh`](sops-encrypt-all.sh) | re-encrypts every plaintext file matched by a `.sops.yaml` `path_regex` into its `*.sops.yaml` sibling |
| [`sops-decrypt-all.sh`](sops-decrypt-all.sh) | decrypts every `*.sops.yaml` into its plaintext sibling (`-f`/`--force` to overwrite local edits) |

## Terragrunt state cleanup

Run from the relevant terragrunt unit directory (not the repo root) — see [`terragrunt/README.md`](../terragrunt/README.md) for the destroy/rebuild workflows these support.

| Script | Purpose |
| --- | --- |
| [`tg-state-rm.sh`](tg-state-rm.sh) | drops state for resources that block `terragrunt destroy` on an unreachable cluster |
| [`volume-remove-state.sh`](volume-remove-state.sh) | drops Proxmox-volume state so `terragrunt destroy` preserves the real disks for reuse |

## kopiur backup/restore

Wrapped by `just backup::kopiur::<list|create|restore>` — see [`kopiur.just`](kopiur.just) and [`docs/backup/kopiur-backup-restore.md`](../docs/backup/kopiur-backup-restore.md) for the day-to-day operational guide.

| Script | Purpose |
| --- | --- |
| [`kopiur-list.sh`](kopiur-list.sh) | lists kopiur `Snapshot` CRs, for one app or every app in scope |
| [`kopiur-create.sh`](kopiur-create.sh) | triggers a manual `Snapshot`, for one app or every app in scope (`--all`) |
| [`kopiur-restore.sh`](kopiur-restore.sh) | restores an app's PVC from its latest snapshot (deletes and repopulates the PVC) |

All three source [`lib/common.sh`](lib/common.sh) for gum-backed logging, environment validation, kubecontext construction, and unrecognized-flag handling shared across them (also sourced by several scripts above, for the same logging).

## Keycloak database restore

Wrapped by `just backup::keycloak::<list|restore>` (see [`keycloak.just`](keycloak.just); the recipes pass their flags straight to the script, which can also be run directly) and always against one environment — see [`docs/identity/keycloak-backup-restore.md`](../docs/identity/keycloak-backup-restore.md#restore) for the procedure, the safety reasoning and the drill record.

| Script | Purpose |
| --- | --- |
| [`keycloak-db-restore.sh`](keycloak-db-restore.sh) | restores the Keycloak database from a `pg_dump` in the `<env>-keycloak-db` bucket: verifies the dump in a scratch database first, then stops Flux/the operator/the dump CronJob, swaps the databases by renaming (the old one is kept) and starts Keycloak again; `--list` shows the available dumps |

Sources [`lib/common.sh`](lib/common.sh) for logging, environment validation and kubecontext construction. Needs `kubectl`, `flux`, `gum` and `jq`.

## Longhorn volume snapshots

Wrapped by `just backup::longhorn-snapshot::<list|create|restore>` — see [`longhorn-snapshot.just`](longhorn-snapshot.just) and [`docs/backup/longhorn-snapshots.md`](../docs/backup/longhorn-snapshots.md). These cover Longhorn's own local snapshots (the `hourly-snapshot`/`daily-backup` `RecurringJob`s plus manual ones), e.g. in environments with no kopiur backup. Hourly snapshots are only retained for ~24 hours, so pick one by its `CREATED` timestamp rather than by day.

| Script | Purpose |
| --- | --- |
| [`longhorn-snapshot-list.sh`](longhorn-snapshot-list.sh) | lists Longhorn `Snapshot` CRs per app (PVC), newest first, for one app or every app in scope |
| [`longhorn-snapshot-create.sh`](longhorn-snapshot-create.sh) | triggers a manual snapshot, for one app or every Longhorn volume in scope (`--all`); manual snapshots are never auto-pruned |
| [`longhorn-snapshot-restore.sh`](longhorn-snapshot-restore.sh) | rolls an app's PVC back to a snapshot: automates the Flux suspend/scale-down/scale-up and pauses for the manual revert in the Longhorn UI; takes a `pre-restore-*` safety snapshot first |

All three source [`lib/common.sh`](lib/common.sh) and [`lib/longhorn.sh`](lib/longhorn.sh) (PVC → Longhorn volume lookup).

## Longhorn volume snapshots

Wrapped by `just backup::longhorn-snapshot::<list|create|restore>` — see [`longhorn-snapshot.just`](longhorn-snapshot.just) and [`docs/backup/longhorn-snapshots.md`](../docs/backup/longhorn-snapshots.md). These cover Longhorn's own local snapshots (the `hourly-snapshot`/`daily-backup` `RecurringJob`s plus manual ones), e.g. in environments with no kopiur backup. Hourly snapshots are only retained for ~24 hours, so pick one by its `CREATED` timestamp rather than by day.

| Script | Purpose |
| --- | --- |
| [`longhorn-snapshot-list.sh`](longhorn-snapshot-list.sh) | lists Longhorn `Snapshot` CRs per app (PVC), newest first, for one app or every app in scope |
| [`longhorn-snapshot-create.sh`](longhorn-snapshot-create.sh) | triggers a manual snapshot, for one app or every Longhorn volume in scope (`--all`); manual snapshots are never auto-pruned |

All three source [`lib/common.sh`](lib/common.sh) and [`lib/longhorn.sh`](lib/longhorn.sh) (PVC → Longhorn volume lookup).

## Proxmox VM snapshot/power management

Wrapped by `just proxmox::snapshot::<create|list|rollback|delete>` and `just proxmox::vm::<list|start|stop|shutdown|reset>` — see [`docs/operations/proxmox-vm-snapshots.md`](../docs/operations/proxmox-vm-snapshots.md) and [`docs/operations/proxmox-vm-power.md`](../docs/operations/proxmox-vm-power.md) for the day-to-day operational guides.

| Script | Purpose |
| --- | --- |
| [`proxmox-snapshot-list.sh`](proxmox-snapshot-list.sh) | lists an environment's VMs and each VM's snapshots |
| [`proxmox-snapshot-create.sh`](proxmox-snapshot-create.sh) | creates a named snapshot on every VM in an environment |
| [`proxmox-snapshot-delete.sh`](proxmox-snapshot-delete.sh) | deletes a named snapshot from every VM that has it (or just `--vmid`) |
| [`proxmox-snapshot-rollback.sh`](proxmox-snapshot-rollback.sh) | rolls every VM in an environment back to a named snapshot and restarts them |
| [`proxmox-vm-list.sh`](proxmox-vm-list.sh) | lists an environment's VMs (no snapshot detail — see `proxmox-snapshot-list.sh` for that) |
| [`proxmox-vm-power.sh`](proxmox-vm-power.sh) | one shared script for `start`/`stop`/`shutdown`/`reset`, parameterized by `--action` |

All source [`lib/proxmox.sh`](lib/proxmox.sh) (Proxmox API auth, VM discovery, task polling) in addition to `lib/common.sh` above.

## RustFS monitoring identity

Run manually (needs 1Password and network access to the RustFS, so not for CI) — see the "RustFS monitoring identity" section of [`terragrunt/README.md`](../terragrunt/README.md) for what the identity is and how to read the output.

| Script | Purpose |
| --- | --- |
| [`rustfs-verify-monitoring.sh`](rustfs-verify-monitoring.sh) | verifies one environment's `<env>-checkmk-monitoring` identity reads quota of its own buckets and is denied everything else (non-mutating) |

Sources [`lib/common.sh`](lib/common.sh) for logging, environment validation and unrecognized-flag handling.

## Keycloak availability drill

Run manually (disrupts the cluster, needs a kubecontext and network access to Keycloak, so not for CI) — see [`docs/identity/keycloak-drain-drill.md`](../docs/identity/keycloak-drain-drill.md) for the procedure, the probes and how to read the report.

| Script | Purpose |
| --- | --- |
| [`keycloak-drain-drill.sh`](keycloak-drain-drill.sh) | drains the node of the Keycloak database (or, with `--observe`, only measures while something else disturbs it) and reports the login outage windows, a pod-event timeline and the image pull times; checks the control plane first and refuses `prod` |

Sources [`lib/common.sh`](lib/common.sh) for logging, environment validation, kubecontext construction and unrecognized-flag handling.
