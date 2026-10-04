---
status: current
---

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
| [`docs-link-check.yml`](../../.github/workflows/docs-link-check.yml) | `lychee --offline` across every `*.md` file, catching a dangling reference to a file/anchor that moved or was deleted — including a non-markdown file a doc links to, so deliberately not `paths:`-filtered to just markdown (see [#1349](https://github.com/isejalabs/homelab/issues/1349)) | ~10s-20s |
| [`labeler.yml`](../../.github/workflows/labeler.yml) | not a validation check — applies `area:*`/`env:*` labels to the PR itself (see below) | ~5s |

Phase 2 — checks that need a live/ephemeral cluster beyond what `bootstrap-apps-test.yml` already covers (`flux-local`, policy checks) — is tracked separately in [#1209](https://github.com/isejalabs/homelab/issues/1209). Anything not covered by the table above is still validated manually via `helmfile template` (used implicitly by `just bootstrap::cluster`) and Flux's own reconciliation status.

## Tool provisioning

Every workflow that needs more than the Ubuntu runner's stock toolset uses [`jdx/mise-action`](https://github.com/jdx/mise-action), which installs whatever the resolved `.mise.toml`'s `[tools]` table declares — that table is shared with local dev (`direnv`/`mise` picks it up on `cd`), so CI and a human running the same script locally get the same tool versions. A workflow's own `install_args:` on the `mise-action` step is only for tools genuinely specific to that one workflow and not worth adding to a shared table (there aren't any of these today — every current `install_args` entry, e.g. `kustomize-build.yml`'s `gum kubeconform kubectl`, actually names tools already declared somewhere, which is harmless redundancy, not a second source of truth).

Three `.mise.toml` files exist, not one: the root one, plus [`terragrunt/.mise.toml`](../../terragrunt/.mise.toml) (`opentofu`/`talosctl`/`terragrunt`) and [`k8s/.mise.toml`](../../k8s/.mise.toml) (`kustomize`/`kubeconform`). mise resolves config by walking up from the current directory and merging every `.mise.toml` it finds, so `terragrunt-validate.yml`/`kustomize-build.yml` set `working_directory: terragrunt`/`working_directory: k8s` on their `mise-action` step (an existing action input) to pick up the directory-scoped file merged with the root one, rather than needing an explicit include. This split exists so a bump to a terragrunt-only or k8s-only tool doesn't also retrigger the *other* workflow — see [#1426](https://github.com/isejalabs/homelab/issues/1426). Tools used by two or more workflows (`kubectl`, `helm`, `gum`, ...) stay in the root file rather than being split further, since moving a shared tool out would need every consumer's `working_directory` updated in lockstep to keep resolving the same pinned version.

`terragrunt-validate.yml` additionally sets `TF_PLUGIN_CACHE_DIR` so its 26 terragrunt units share one provider-download cache within a run, and persists that cache *across* runs too via `actions/cache`, keyed on every `terragrunt.hcl` plus `terragrunt/.mise.toml` (see [#1416](https://github.com/isejalabs/homelab/issues/1416)).

## PR labeling and Mergify

[`.github/labeler.yml`](../../.github/labeler.yml), run by `labeler.yml` on `pull_request_target`, applies `area:*` labels (by which top-level directories changed) and `env:*` labels (by which environment's overlay/terragrunt unit changed) to every PR. These aren't purely cosmetic: Mergify ([`.github/mergify.yml`](../../.github/mergify.yml)) reads `label=pr-type:renovate` and `label=env:head`/`label=updateType:minor`-style conditions to decide which Renovate PRs to auto-merge. `area:terraform` covers `.mise.toml`/`mise.lock` version bumps too (see [#1416](https://github.com/isejalabs/homelab/issues/1416)) — accepting that this flags on any tool's bump in that shared file, not just terragrunt/opentofu's, since path matching is file-level, not line-level. `area:docs` had a real mislabeling bug (fixed in [#1416](https://github.com/isejalabs/homelab/issues/1416)/[#1425](https://github.com/isejalabs/homelab/pull/1425) — see those for the two-part history) and now matches `docs/**`/`**/README.md` only, deliberately not the broader `**/*.md` that caused it. **Known caveat as of this writing**: a workflow reading `github.event.pull_request.labels` can't reliably see a label this same PR's `labeler.yml` run is about to add, since both trigger off the same webhook event but run as independent jobs — don't gate CI on labels for this reason (see #1416's "Alternatives considered").

## What isn't covered here

- Phase 2 (live/ephemeral-cluster checks beyond `bootstrap-apps-test.yml`, policy checks) — [#1209](https://github.com/isejalabs/homelab/issues/1209).
- Reducing CI runtime (path-based skipping, provider-download caching) — [#1416](https://github.com/isejalabs/homelab/issues/1416).
- Wiring any of the above up as a required branch-protection check — not yet planned.
