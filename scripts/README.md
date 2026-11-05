Helper scripts that don't belong to a single `k8s/`/`terragrunt/` unit — CI validation entry points, bulk SOPS encrypt/decrypt, Terragrunt state cleanup, kopiur backup/restore operations, the Keycloak database restore, Checkmk site checks, and Proxmox VM snapshot/power management. Each script documents its own purpose and usage in a header comment (see the linked file itself for the full explanation); this README is an index, not a duplicate of that. Every file in this folder, `just` modules and helpers included, must be linked from here — [`check-scripts-index.sh`](check-scripts-index.sh) fails CI otherwise.

Shell scripts default to `#!/bin/sh` unless a feature genuinely requires bash (e.g. arrays, `[[ ]]`, `set -o pipefail`) — most here are plain POSIX `sh`. The `kopiur-*.sh`, `longhorn-snapshot-*.sh` and `proxmox-*.sh` scripts are bash (arrays) and, unlike most others here, are also wrapped by `just` recipes rather than run directly — see [`kopiur.just`](kopiur.just) and [`proxmox-snapshot.just`](proxmox-snapshot.just)/[`proxmox-vm.just`](proxmox-vm.just).

## `just` modules

The root [`.justfile`](../.justfile) loads `backup` and `proxmox` from here; each parent module loads the domain modules below it, so the recipe name mirrors the nesting (`just backup::kopiur::list`, `just proxmox::vm::start`). The recipes only wrap the scripts of the same domain, which are indexed in the sections further down.

| Module | Recipes |
| --- | --- |
| [`backup.just`](backup.just) | parent of `kopiur`, `longhorn-snapshot` and `keycloak` — `just backup::<module>::<recipe>` |
| [`kopiur.just`](kopiur.just) | `list`, `create`, `restore`, `bypass-restore`, `migrate`, `convert-storage-class` — see [kopiur backup/restore](#kopiur-backuprestore) |
| [`longhorn-snapshot.just`](longhorn-snapshot.just) | `list`, `create`, `restore` — see [Longhorn volume snapshots](#longhorn-volume-snapshots) |
| [`keycloak.just`](keycloak.just) | `list`, `restore` — see [Keycloak database restore](#keycloak-database-restore) |
| [`proxmox.just`](proxmox.just) | parent of `snapshot` and `vm` — `just proxmox::<module>::<recipe>` |
| [`proxmox-snapshot.just`](proxmox-snapshot.just) | `create`, `list`, `delete`, `rollback` — see [Proxmox VM snapshot/power management](#proxmox-vm-snapshotpower-management) |
| [`proxmox-vm.just`](proxmox-vm.just) | `list`, `start`, `shutdown`, `stop`, `reset` — see [Proxmox VM snapshot/power management](#proxmox-vm-snapshotpower-management) |

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
| [`check-unit-readmes.sh`](check-unit-readmes.sh) | every unit under `k8s/{apps,infra}/*/*` with a `flux/` folder has a `README.md` that follows the template in `k8s/README.md`: a level-1 title, the required `##` headings in order (extra sections allowed) the four rows of the `At a glance` table and no URL in a code span in `Access`, an entry in the docs navigation `.ci/mkdocs/mkdocs.yml`, and the `Namespace`, `Flux Kustomization` (name and `dependsOn`) and `Runs in` (environments and Flux set) rows against `base/kustomization.yaml`, `flux/ks.yaml`, the Flux sets and `flux/envs/*` (runs in the `docs-link-check` workflow; optional repo-root argument to check a copy of the tree) |
| [`check-unit-readme-hostnames.sh`](check-unit-readme-hostnames.sh) | every hostname linked in the `Access` section of a unit README is served by that unit's rendered overlay `k8s/<unit>/envs/<env>` (environment derived from the host; renders with `kubectl kustomize`, set `KUSTOMIZE` to use another command; runs in the `docs-link-check` workflow; optional repo-root argument) |
| [`test-readme-access.sh`](test-readme-access.sh) | unit test of the host-to-environment mapping (including the prod exception `auth.iseja.net`) and of the link extraction behind `check-unit-readme-hostnames.sh` (runs in the `docs-link-check` workflow) |
| [`check-scripts-index.sh`](check-scripts-index.sh) | every file under `scripts/` is linked from its nearest `README.md`, and no README repeats a `##` heading (runs in the `docs-link-check` workflow; optional repo-root argument to check a copy of the tree) |
| [`check-sorting.py`](check-sorting.py) | leading-field/`metadata` key ordering (`.agents/instructions/sorting.md`) — needs [`requirements.txt`](requirements.txt) installed first |
| [`install-actionlint.sh`](install-actionlint.sh) | not a check itself — installs the pinned `actionlint` binary the `actionlint` workflow lints with |
| [`renovate-config-validator-version.sh`](renovate-config-validator-version.sh) | not a check itself — sourced to pin the `renovate-config-validator` version the `renovate-config-validate` workflow uses |

`check-workloads-catalog.sh` and `check-unit-readmes.sh` source [`lib/flux-sets.sh`](lib/flux-sets.sh) (which Flux set lists a unit, which environments run it), and `check-unit-readme-hostnames.sh` also [`lib/readme-access.sh`](lib/readme-access.sh) (hostnames linked in `Access`, host to environment). Both need only POSIX `sh`, `awk` and `sed`, unlike `lib/common.sh`.

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

Wrapped by `just backup::kopiur::<list|create|restore|bypass-restore|migrate|convert-storage-class>` — see [`kopiur.just`](kopiur.just) and [`docs/backup/kopiur-backup-restore.md`](../docs/backup/kopiur-backup-restore.md) for the day-to-day operational guide.

| Script | Purpose |
| --- | --- |
| [`kopiur-list.sh`](kopiur-list.sh) | lists kopiur `Snapshot` CRs, for one app or every app in scope |
| [`kopiur-create.sh`](kopiur-create.sh) | triggers a manual `Snapshot`, for one app or every app in scope (`--all`) |
| [`kopiur-restore.sh`](kopiur-restore.sh) | restores an app's PVC from its latest snapshot (deletes and repopulates the PVC) |
| [`kopiur-bypass-restore.sh`](kopiur-bypass-restore.sh) | gives an app a blank PVC without deleting its kopiur backups, for importing data by other means (e.g. from another environment); interactive |
| [`kopiur-migrate-pvc.sh`](kopiur-migrate-pvc.sh) | copies an app's data from an old PVC onto its new kopiur-managed PVC ahead of a `claimName`/`existingClaim` cut-over; leaves the owning Flux object suspended and the app scaled to 0 |
| [`kopiur-convert-storageclass.sh`](kopiur-convert-storageclass.sh) | converts a kopiur-managed PVC onto a different StorageClass in place (copies the data to a new PVC and rebinds it under the original name), e.g. ext4 to xfs |

All six source [`lib/common.sh`](lib/common.sh) for gum-backed logging, environment validation, kubecontext construction, and unrecognized-flag handling shared across them (also sourced by several scripts above, for the same logging).

## Keycloak database restore

Wrapped by `just backup::keycloak::<list|restore>` (see [`keycloak.just`](keycloak.just); the recipes pass their flags straight to the script, which can also be run directly) and always against one environment — see [`docs/identity/keycloak-backup-restore.md`](../docs/identity/keycloak-backup-restore.md#restore) for the procedure, the safety reasoning and the drill record.

| Script | Purpose |
| --- | --- |
| [`keycloak-db-restore.sh`](keycloak-db-restore.sh) | restores the Keycloak database from a `pg_dump` in the `<env>-keycloak-db` bucket: verifies the dump in a scratch database first, then stops Flux/the operator/the dump CronJob, swaps the databases by renaming (the old one is kept) and starts Keycloak again; `--list` shows the available dumps; `--identity <file>` is the age private key for an encrypted `*.dump.age` dump |

Sources [`lib/common.sh`](lib/common.sh) for logging, environment validation and kubecontext construction. Needs `kubectl`, `flux`, `gum` and `jq`.

## Checkmk checks

Run manually against one Checkmk site; see [`docs/identity/checkmk-sso.md`](../docs/identity/checkmk-sso.md#regression-check-agent-registration).

| Script | Purpose |
| --- | --- |
| [`checkmk-agent-registration-check.sh`](checkmk-agent-registration-check.sh) | non-destructive regression check that agent registration still works on a site: a wrong password is refused with 401, and the registration user is accepted for an unknown host name (404 `does not exist`), without registering anything; the secret comes from `CMK_REGISTRATION_PASSWORD` |

Sources [`lib/common.sh`](lib/common.sh) for logging. Needs `curl` and `gum`.

## Longhorn volume snapshots

Wrapped by `just backup::longhorn-snapshot::<list|create|restore>` — see [`longhorn-snapshot.just`](longhorn-snapshot.just) and [`docs/backup/longhorn-snapshots.md`](../docs/backup/longhorn-snapshots.md). These cover Longhorn's own local snapshots (the `hourly-snapshot`/`daily-backup` `RecurringJob`s plus manual ones), e.g. in environments with no kopiur backup. Hourly snapshots are only retained for ~24 hours, so pick one by its `CREATED` timestamp rather than by day.

| Script | Purpose |
| --- | --- |
| [`longhorn-snapshot-list.sh`](longhorn-snapshot-list.sh) | lists Longhorn `Snapshot` CRs per app (PVC), newest first, for one app or every app in scope |
| [`longhorn-snapshot-create.sh`](longhorn-snapshot-create.sh) | triggers a manual snapshot, for one app or every Longhorn volume in scope (`--all`); manual snapshots are never auto-pruned |
| [`longhorn-snapshot-restore.sh`](longhorn-snapshot-restore.sh) | rolls an app's PVC back to a snapshot: automates the Flux suspend/scale-down/scale-up and pauses for the manual revert in the Longhorn UI; takes a `pre-restore-*` safety snapshot first |

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

## Agent tooling (Mink for Codex)

Not a repo workflow: the adapter that [`.codex/hooks.json`](../.codex/hooks.json) runs on Codex hook events, so Codex sessions feed Mink the same file events Claude Code does. [`mink-codex-hook.md`](mink-codex-hook.md) explains what it translates and what it deliberately does not.

| Script | Purpose |
| --- | --- |
| [`mink-codex-hook.py`](mink-codex-hook.py) | translates Codex hook events (`apply_patch`, standalone `cat`/`head`/`tail`/`sed -n` reads) into Mink's Claude-style file events; never executes shell text |
| [`test-mink-codex-hook.py`](test-mink-codex-hook.py) | unit tests of that translation, run with `python3 scripts/test-mink-codex-hook.py` |
| [`mink-codex-hook.md`](mink-codex-hook.md) | what the adapter does, its limits, and how to smoke-test it |
