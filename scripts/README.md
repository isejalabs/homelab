Helper scripts that don't belong to a single `k8s/`/`terragrunt/` unit — CI validation entry points, bulk SOPS encrypt/decrypt, Terragrunt state cleanup, kopiur backup/restore operations, and Proxmox VM snapshot/power management. Each script documents its own purpose and usage in a header comment (see the linked file itself for the full explanation); this README is an index, not a duplicate of that.

Shell scripts default to `#!/bin/sh` unless a feature genuinely requires bash (e.g. arrays, `[[ ]]`, `set -o pipefail`) — most here are plain POSIX `sh`. The `kopiur-*.sh` and `proxmox-*.sh` scripts are bash (arrays) and, unlike most others here, are also wrapped by `just` recipes rather than run directly — see [`kopiur.just`](kopiur.just) and [`proxmox-snapshot.just`](proxmox-snapshot.just)/[`proxmox-vm.just`](proxmox-vm.just).

## CI validation

Invoked by the matching `.github/workflows/*.yml` on every PR and push to `main` (see the root [`CLAUDE.md`](../CLAUDE.md)'s CI section for the full list and what each gate covers).

| Script | Checks |
| --- | --- |
| [`kustomize-build-all.sh`](kustomize-build-all.sh) | `kubectl kustomize` + kubeconform across every `k8s/` overlay |
| [`terragrunt-validate-all.sh`](terragrunt-validate-all.sh) | `terragrunt init -backend=false` + `validate` across every `terragrunt/` unit |
| [`helmfile-template-all.sh`](helmfile-template-all.sh) | renders `k8s/bootstrap/helmfile/{crds,apps}` for every environment |
| [`flate-test-all.sh`](flate-test-all.sh) | `flate test all` against every environment's top-level Flux sync target |
| [`bootstrap-apps-ci-test.sh`](bootstrap-apps-ci-test.sh) | the bootstrap `apps` helmfile stage, against an ephemeral kind cluster |
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

Wrapped by `just backup::kopiur::<list|create|restore>` — see [`kopiur.just`](kopiur.just) and [`docs/kopiur-backup-restore.md`](../docs/kopiur-backup-restore.md) for the day-to-day operational guide.

| Script | Purpose |
| --- | --- |
| [`kopiur-list.sh`](kopiur-list.sh) | lists kopiur `Snapshot` CRs, for one app or every app in scope |
| [`kopiur-create.sh`](kopiur-create.sh) | triggers a manual `Snapshot`, for one app or every app in scope (`--all`) |
| [`kopiur-restore.sh`](kopiur-restore.sh) | restores an app's PVC from its latest snapshot (deletes and repopulates the PVC) |

All three source [`lib/common.sh`](lib/common.sh) for gum-backed logging, environment validation, kubecontext construction, and unrecognized-flag handling shared across them (also sourced by several scripts above, for the same logging).

## Proxmox VM snapshot/power management

Wrapped by `just proxmox::snapshot::<create|list|rollback|delete>` and `just proxmox::vm::<list|start|stop|shutdown|reset>` — see [`docs/proxmox-vm-snapshots.md`](../docs/proxmox-vm-snapshots.md) and [`docs/proxmox-vm-power.md`](../docs/proxmox-vm-power.md) for the day-to-day operational guides.

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

## Cluster maintenance

| Script | Purpose |
| --- | --- |
| [`upgrade-k8s.sh`](upgrade-k8s.sh) | upgrades the Kubernetes version on an already-provisioned Talos cluster in place |
