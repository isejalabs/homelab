# CI

There's no application source code in this repo, so CI (`.github/workflows/`) is limited to static validation rather than tests: linting/formatting checks, rendering every templated manifest, and (for `bootstrap-apps-test.yml`) actually applying a subset of the bootstrap `helmfile` against a throwaway cluster. Everything below runs on every `pull_request` and every `push` to `main`, and — per [#1206](https://github.com/isejalabs/homelab/issues/1206) phase 1 — none of it is wired up as a required branch-protection check yet, so a red run doesn't block a merge at the GitHub level (treat it as if it did anyway — see the "PR discipline" section above).

## Workflows

| Workflow | Checks | Typical runtime |
| --- | --- | --- |
| [`pre-commit.yml`](../../.github/workflows/pre-commit.yml) | the repo's own `pre-commit` hooks (`.pre-commit-config.yaml`: `forbid-secrets`, `validate-sops`) | ~10s |
| [`kustomize-build.yml`](../../.github/workflows/kustomize-build.yml) | `kustomize build` + `kubeconform` across every `k8s/` overlay (`scripts/kustomize-build-all.sh`) | ~1m15s-1m30s |
| [`terragrunt-validate.yml`](../../.github/workflows/terragrunt-validate.yml) | `tofu fmt -check`, `terragrunt hcl format --check`, and `terragrunt init -backend=false` + `validate` across every `terragrunt/` unit (`scripts/terragrunt-validate-all.sh`) | ~2m20s-3m0s, occasionally much longer |
| [`bootstrap-apps-test.yml`](../../.github/workflows/bootstrap-apps-test.yml) | the bootstrap `helmfile` "apps" stage against an ephemeral `kind` cluster (`scripts/bootstrap-apps-ci-test.sh`) — the only workflow that actually applies anything, rather than just rendering/linting | ~2m30s-3m55s |
| [`helmfile-template.yml`](../../.github/workflows/helmfile-template.yml) | renders `k8s/bootstrap/helmfile/{crds,apps}` for every environment, to catch `.gotmpl` errors (`scripts/helmfile-template-all.sh`) | ~20s-30s |
| [`flate-test.yml`](../../.github/workflows/flate-test.yml) | `flate test all` — cross-resource Flux validation against every environment's top-level sync target (`scripts/flate-test-all.sh`) | ~20s-45s |
| [`renovate-config-validate.yml`](../../.github/workflows/renovate-config-validate.yml) | `renovate-config-validator` against `.github/renovate.json5` and its includes | ~30s-40s |
| [`check-sorting.yml`](../../.github/workflows/check-sorting.yml) | leading-field/`metadata` key ordering conformance with [`.agents/instructions/sorting.md`](../../.agents/instructions/sorting.md) (`scripts/check-sorting.py`) — partial: that ordering only, not full list-sorting | ~10s |
| [`actionlint.yml`](../../.github/workflows/actionlint.yml) | lints the workflow files themselves | ~15s-20s |
| [`labeler.yml`](../../.github/workflows/labeler.yml) | not a validation check — applies `area:*`/`env:*` labels to the PR itself (see below) | ~5s |

Phase 2 — checks that need a live/ephemeral cluster beyond what `bootstrap-apps-test.yml` already covers (`flux-local`, policy checks) — is tracked separately in [#1209](https://github.com/isejalabs/homelab/issues/1209). Anything not covered by the table above is still validated manually via `helmfile template` (used implicitly by `just bootstrap::cluster`) and Flux's own reconciliation status.

## Tool provisioning

Every workflow that needs more than the Ubuntu runner's stock toolset uses [`jdx/mise-action`](https://github.com/jdx/mise-action), which installs whatever [`.mise.toml`](../../.mise.toml)'s `[tools]` table declares — that table is shared with local dev (`direnv`/`mise` picks it up on `cd`), so CI and a human running the same script locally get the same tool versions. A workflow's own `install_args:` on the `mise-action` step is only for tools genuinely specific to that one workflow and not worth adding to the shared table (there aren't any of these today — every current `install_args` entry, e.g. `kustomize-build.yml`'s `gum kubeconform kubectl`, actually names tools already in `.mise.toml` too, which is harmless redundancy, not a second source of truth). `terragrunt-validate.yml` additionally sets `TF_PLUGIN_CACHE_DIR` to a shared directory so its 26 terragrunt units don't each download their own copy of every OpenTofu provider — this cache is only shared *within* one run today, not persisted across runs (see [#1416](https://github.com/isejalabs/homelab/issues/1416)).

## PR labeling and Mergify

[`.github/labeler.yml`](../../.github/labeler.yml), run by `labeler.yml` on `pull_request_target`, applies `area:*` labels (by which top-level directories changed) and `env:*` labels (by which environment's overlay/terragrunt unit changed) to every PR. These aren't purely cosmetic: Mergify ([`.github/mergify.yml`](../../.github/mergify.yml)) reads `label=pr-type:renovate` and `label=env:head`/`label=updateType:minor`-style conditions to decide which Renovate PRs to auto-merge. **Known caveats as of this writing** (see [#1416](https://github.com/isejalabs/homelab/issues/1416) for the full investigation, not re-litigated here): `area:terraform` doesn't cover `.mise.toml`/`mise.lock` version bumps, `area:docs`'s glob rule has a bug that makes it over-match unrelated files, and — separately from either bug — a workflow reading `github.event.pull_request.labels` can't reliably see a label this same PR's `labeler.yml` run is about to add, since both trigger off the same webhook event but run as independent jobs.

## What isn't covered here

- Phase 2 (live/ephemeral-cluster checks beyond `bootstrap-apps-test.yml`, policy checks) — [#1209](https://github.com/isejalabs/homelab/issues/1209).
- Reducing CI runtime (path-based skipping, provider-download caching) — [#1416](https://github.com/isejalabs/homelab/issues/1416).
- Wiring any of the above up as a required branch-protection check — not yet planned.
