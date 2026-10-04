---
status: current
---

# CI

There's no application source code in this repo, so CI (`.github/workflows/`) is limited to static validation rather than tests: linting/formatting checks, rendering every templated manifest, and (for `bootstrap-apps-test.yml`) actually applying a subset of the bootstrap `helmfile` against a throwaway cluster. All 9 workflows now trigger on every `pull_request`/push to `main`. `kustomize-build`, `terragrunt-validate`, and `bootstrap-apps-test` each run a cheap `changes` job first (`dorny/paths-filter`) and gate their real work on it with a job-level `if:`, rather than a workflow-level `paths:` trigger filter — a job skipped this way reports status `Success`, unlike a workflow that never starts at all. That distinction is what makes a check safe to add as a required status check: GitHub's required-status-checks feature has no "only count checks that actually ran" semantic, so a workflow that never starts at all looks identical to "still running" and blocks merge forever (see [#1511](https://github.com/isejalabs/homelab/issues/1511) for the full reasoning).

7 of the 9 are required status checks on `main`'s branch protection today — a red or missing run on one of those blocks merge at the GitHub level, not just by convention. The 3 just-converted ones aren't required *yet*: #1511 proved the "runs for real" path (editing the workflow files themselves necessarily triggers them), but the "skips cleanly" path still needs confirming on an ordinary PR that doesn't touch `k8s/`, `terragrunt/`, or `k8s/bootstrap/helmfile/` before they're added too — at which point no branch-protection reconfiguration is needed, since the check names didn't change.

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

Mergify's own merge conditions never check CI status — only labels. Before `main`'s branch protection existed, that meant a label match alone was enough for Mergify to merge, regardless of whether the required checks above had even finished. Branch protection now closes that gap for free: Mergify merges via a normal (non-bypass) write operation, so GitHub itself withholds the merge until the required checks pass, on top of Mergify's own label conditions — no change to `mergify.yml` was needed.

## What isn't covered here

- Phase 2 (live/ephemeral-cluster checks beyond `bootstrap-apps-test.yml`, policy checks) — [#1209](https://github.com/isejalabs/homelab/issues/1209).
- Reducing CI runtime (path-based skipping, provider-download caching) — [#1416](https://github.com/isejalabs/homelab/issues/1416).
- Adding the 3 just-converted workflows to `main`'s required checks, once the skip path is confirmed on an ordinary PR — [#1511](https://github.com/isejalabs/homelab/issues/1511).
