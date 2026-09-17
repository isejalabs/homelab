Helper scripts that don't belong to a single `k8s/`/`terragrunt/` unit — CI validation entry points, bulk SOPS encrypt/decrypt, Terragrunt state cleanup, and kopiur backup/restore operations. Each script documents its own purpose and usage in a header comment (see the linked file itself for the full explanation); this README is an index, not a duplicate of that.

Shell scripts default to `#!/bin/sh` unless a feature genuinely requires bash (e.g. arrays, `[[ ]]`, `set -o pipefail`) — most here are plain POSIX `sh`. Three scripts (`kopiur-list.sh`, `kopiur-create.sh`, `kopiur-restore.sh`) are also wrapped by `just` recipes rather than run directly — see [`kopiur.just`](kopiur.just).

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

## Cluster maintenance

| Script | Purpose |
| --- | --- |
| [`upgrade-k8s.sh`](upgrade-k8s.sh) | upgrades the Kubernetes version on an already-provisioned Talos cluster in place |
