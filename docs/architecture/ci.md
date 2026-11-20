---
status: current
---

# CI

There is no application source code in this repo, so CI focuses on infrastructure and configuration validation rather than application unit tests: linting and formatting, manifest rendering and validation, plus a bootstrap test that applies part of the `helmfile` against a throwaway cluster. The repository has 15 workflow files: 11 validation workflows, three non-required docs checks ([`docs-mermaid-check.yml`](../../.github/workflows/docs-mermaid-check.yml), [`spell-check.yml`](../../.github/workflows/spell-check.yml) and the scheduled [`docs-link-check-external.yml`](../../.github/workflows/docs-link-check-external.yml), which has no `pull_request` trigger), and one PR-labeling workflow. All 11 validation workflows run on every `pull_request` and push to `main`; `labeler.yml` runs on `pull_request_target`. 10 of the 11 validation workflows are required status checks on `main` (`docs-build` is not required yet, see its row below): `pre-commit`, `kustomize-build`, `terragrunt-validate`, `bootstrap-apps-test`, `helmfile-template`, `flate-test`, `renovate-config-validate`, `check-sorting`, `actionlint`, and `docs-link-check`. Keep this list in sync with `main`'s branch protection when required checks change. A red or missing required check blocks merge at the GitHub level, not just by convention. `kustomize-build`, `terragrunt-validate`, and `bootstrap-apps-test` each run a cheap `changes` job first (`dorny/paths-filter`, with `predicate-quantifier: 'some-with-excludes'` — the library's default doesn't actually honor `!`-prefixed exclusion patterns, confirmed the hard way on [#1511](https://github.com/isejalabs/homelab/issues/1511)) and gate their real work on it with a job-level `if:`, rather than a workflow-level `paths:` trigger filter. A job skipped this way reports status `Success`, unlike a workflow that never starts at all — confirmed live on [PR #1517](https://github.com/isejalabs/homelab/pull/1517), a genuinely unrelated change, where all three showed `skipping` rather than running for real or blocking. That distinction is what made adding them safe: GitHub's required-status-checks feature has no "only count checks that actually ran" semantic, so a workflow that never starts at all looks identical to "still running" and blocks merge forever.

## Workflows

| Workflow | Role | Checks | Typical runtime |
| --- | --- | --- | --- |
| [`pre-commit.yml`](../../.github/workflows/pre-commit.yml) | Required validation | the repo's own `pre-commit` hooks (`.pre-commit-config.yaml`: `forbid-secrets`, `validate-sops` and the `disclosure-*` guard, see [Disclosure guard](#disclosure-guard)), then `scripts/ci/test-disclosure-hooks.sh`, which seeds one synthetic violation per pattern class and expects the guard to fail on it. A second job, `script-lint`, is advisory and not required: `shellcheck` and `just --fmt --check` (see [Script lint](#script-lint-advisory)) | ~10s-30s |
| [`kustomize-build.yml`](../../.github/workflows/kustomize-build.yml) | Required validation | `kustomize build` + `kubeconform` across every `k8s/` overlay, plus a guard that no `flux/ks.yaml` sets `spec.targetNamespace`, a guard that no `kustomization.yaml` lists a remote (`https://`, `git@`, go-getter) resource, a check that every vendored upstream manifest under a `vendor/` directory is byte-identical to the upstream file named in its `kustomization.yaml` (`scripts/ci/vendor-manifests.sh check`) and a check that each `keycloak-realm` Terragrunt unit's `keycloak_url` equals the hostname its environment's Keycloak overlay serves (`scripts/ci/kustomize-build-all.sh`) | ~1m15s-1m30s |
| [`terragrunt-validate.yml`](../../.github/workflows/terragrunt-validate.yml) | Required validation | `tofu fmt -check`, `terragrunt hcl format --check`, and `terragrunt init -backend=false` + `validate` across every `terragrunt/` unit (`scripts/ci/terragrunt-validate-all.sh`); a `prod` or `qa` unit without a committed `.terraform.lock.hcl` fails, and those units are init'd with `-lockfile=readonly`, so an incomplete lock fails too (see [Provider lock files](../../terragrunt/README.md#provider-lock-files)) | ~2m20s-3m0s, occasionally much longer |
| [`bootstrap-apps-test.yml`](../../.github/workflows/bootstrap-apps-test.yml) | Required validation | the bootstrap `helmfile` "apps" stage against an ephemeral `kind` cluster (`scripts/ci/bootstrap-apps-ci-test.sh`) — the only workflow that actually applies anything, rather than just rendering/linting | ~2m30s-3m55s |
| [`helmfile-template.yml`](../../.github/workflows/helmfile-template.yml) | Required validation | renders `k8s/bootstrap/helmfile/{crds,apps}` for every environment, to catch `.gotmpl` errors (`scripts/ci/helmfile-template-all.sh`) | ~20s-30s |
| [`flate-test.yml`](../../.github/workflows/flate-test.yml) | Required validation | `flate test all` — cross-resource Flux validation against every environment's top-level sync target (`scripts/ci/flate-test-all.sh`) | ~20s-45s |
| [`renovate-config-validate.yml`](../../.github/workflows/renovate-config-validate.yml) | Required validation | `renovate-config-validator` against `.github/renovate.json5` and its includes | ~30s-40s |
| [`check-sorting.yml`](../../.github/workflows/check-sorting.yml) | Required validation | leading-field/`metadata` key ordering conformance with [`.agents/instructions/sorting.md`](../../.agents/instructions/sorting.md) (`scripts/ci/check-sorting.py`) — partial: that ordering only, not full list-sorting | ~10s |
| [`actionlint.yml`](../../.github/workflows/actionlint.yml) | Required validation | lints the workflow files themselves | ~15s-20s |
| [`docs-link-check.yml`](../../.github/workflows/docs-link-check.yml) | Required validation | `lychee --offline --include-fragments` across every `*.md` file, catching a dangling reference to a file or `#anchor` that moved or was deleted — including a non-markdown file a doc links to, so deliberately not `paths:`-filtered to just markdown (see [#1349](https://github.com/isejalabs/homelab/issues/1349)); also runs `scripts/ci/check-workloads-catalog.sh`, which fails when the tables in [`workloads.md`](workloads.md) and the Flux sets in `k8s/bootstrap/cluster/flux/sets/` disagree (a unit missing from the table, a row without a unit, or a different `Flux set`) and `scripts/ci/check-docs-nav.sh`, which fails when a Markdown file that the docs site serves is not listed in `nav` of [`mkdocs.yml`](../../.ci/mkdocs/mkdocs.yml) (no sidebar entry) or a `nav` entry points at a missing file, and `scripts/ci/check-scripts-index.sh`, which fails when a file under `scripts/` is not linked from its nearest `README.md` or a README repeats a `##` heading ([#2177](https://github.com/isejalabs/homelab/issues/2177)) and `scripts/ci/check-unit-readmes.sh`, which fails when a unit under `k8s/apps` or `k8s/infra` has no `README.md` or one that lacks the headings or `At a glance` rows of the [unit README template](../../k8s/README.md#readme-of-an-appinfra-unit) or writes a URL in `Access` as a code span instead of a clickable link, or is missing from the docs site navigation, or whose `Namespace`, `Flux Kustomization` or `Runs in` row disagrees with `base/kustomization.yaml`, `flux/ks.yaml`, the Flux sets or `flux/envs/*` (grammar: [README of an app/infra unit](../../k8s/README.md#facts-checked-against-the-manifests)) and `scripts/ci/check-unit-readme-hostnames.sh`, which renders the overlay with `kubectl kustomize` (the one tool this workflow installs besides `lychee`, offline, a few seconds) and fails when a hostname linked in a README's `Access` section is not served by the unit's overlay for that environment — all folded in here rather than made separate required checks, because they are docs-consistency checks that need no tooling beyond POSIX `sh`/`awk` (and `kubectl` for the hostnames) and should run on every PR, also when only a manifest changed and its README did not | ~20s-40s |
| [`docs-build.yml`](../../.github/workflows/docs-build.yml) | Validation, not required yet | `mkdocs build --strict` of the documentation site ([ADR 0017](../decisions/0017-docs-site-generator.md), config in [`.ci/mkdocs/`](../../.ci/mkdocs)), so a broken relative link or `#anchor` fails the build. Gated by the same job-level `dorny/paths-filter` pattern as `kustomize-build`, so a skip is safe to require later. On `main` it also uploads the site and, only while the repository variable `DOCS_PAGES_PUBLISH` is `true`, deploys it to GitHub Pages (`pages: write`, `id-token: write` on that job only) | ~30s |
| [`docs-mermaid-check.yml`](../../.github/workflows/docs-mermaid-check.yml) | Non-required validation | parses every `mermaid` fence in the `*.md` files with the Mermaid CLI (`mmdc`, pinned in [`docs/.mise.toml`](../../docs/.mise.toml)); GitHub renders invalid Mermaid as an error box instead of failing, so this is what catches a syntax error. Runs only when a Markdown file, the pin or the workflow changes, which is why it is not a required check; see [Diagrams](../README.md#diagrams) for the conventions | ~30s-1m |
| [`spell-check.yml`](../../.github/workflows/spell-check.yml) | Advisory, not required | `typos` over every `*.md` file (see [Spell check](#spell-check-advisory)) | ~15s |
| [`docs-link-check-external.yml`](../../.github/workflows/docs-link-check-external.yml) | Scheduled, never on a PR | `lychee` online over the external URLs in every `*.md` file (see [External link check](#external-link-check-scheduled)) | not run yet, see the follow-ups of the introducing PR |
| [`labeler.yml`](../../.github/workflows/labeler.yml) | PR automation | applies `area:*`/`env:*` labels to the PR itself (see below) | ~5s |

Phase 2 — checks that need a live/ephemeral cluster beyond what `bootstrap-apps-test.yml` already covers (`flux-local`, policy checks) — is tracked separately in [#1209](https://github.com/isejalabs/homelab/issues/1209). Anything not covered by the table above is still validated manually via `helmfile template` (used implicitly by `just bootstrap::cluster`) and Flux's own reconciliation status.

## How a pull request reaches `main`

The diagram shows which workflows a pull request triggers and where the merge decision sits. Which Renovate pull requests Mergify merges on its own is a separate decision, drawn in [`update-handling.md`](../operations/update-handling.md#how-a-renovate-pull-request-gets-merged).

```mermaid
flowchart LR
    accTitle: Pull request path through CI, labeling and Mergify
    accDescr: A pull request triggers the 11 validation workflows and the docs mermaid check on the pull_request event, and the labeler workflow on pull_request_target. Ten of the validation workflows are required status checks, while docs-build, docs-mermaid-check, spell-check and the script-lint job of the pre-commit workflow are not. The labeler adds area and env labels that Mergify reads to decide whether it may merge a Renovate pull request. A human or Mergify can request the merge, and branch protection on main withholds it until every required check has passed.

    pr["Pull request opened or updated"]

    pr -->|"pull_request"| required["10 required checks<br/>pre-commit, kustomize-build, terragrunt-validate,<br/>bootstrap-apps-test, helmfile-template, flate-test,<br/>renovate-config-validate, check-sorting, actionlint,<br/>docs-link-check"]
    pr -->|"pull_request"| optional["not required<br/>docs-build, docs-mermaid-check, spell-check,<br/>script-lint"]
    pr -->|"pull_request_target"| labeler["labeler.yml<br/>adds area and env labels"]

    labeler --> mergify["Mergify<br/>reads pr-type, updateType, updateStrategy<br/>and env labels"]
    mergify -->|"label conditions match: requests the merge"| gate
    human["human review"] -->|"requests the merge"| gate
    required --> gate{"branch protection on main<br/>all required checks green?"}
    gate -->|"yes"| main["merged to main<br/>Flux reconciles it"]
    gate -->|"no"| blocked["merge withheld"]
```

Mergify never looks at CI status itself; the required checks are what stop a merge it requests (see [PR labeling and Mergify](#pr-labeling-and-mergify)).

## Disclosure guard

[ADR 0019](../decisions/0019-public-disclosure-policy.md) keeps personal identifiers out of the repository, and the guard checks it in two parts. Both are hooks of `.pre-commit-config.yaml`, so the required `pre-commit` check enforces the public part on every pull request (no change to `main`'s branch protection) and a local `pre-commit` run enforces both before a commit.

### Public pattern classes

Four `pygrep` hooks (a regular expression per line, built into `pre-commit`, no extra tool) flag a class of values. Only classes are in the repository, never a list of specific strings: such a list would publish exactly what it forbids.

| Hook | Flags | Lets through |
| --- | --- | --- |
| `disclosure-email` | an email address | placeholder domains (`example.com`, `example.org`, `example.net` and subdomains), the reserved TLDs `.invalid`, `.test`, `.local`, `.localhost`, `.example`, the local parts `noreply`, `no-reply`, `root` and `git` (bots, `ssh root@host`), `noreply.github.com`, a principal in an uppercase Kerberos realm (`user@REALM.EXAMPLE`), the address inside a `lore.kernel.org`/`lore.proxmox.com` mailing-list URL |
| `disclosure-mac` | a MAC address with `:` or `-` separators | all-zero, broadcast, `AA:BB:CC:DD:EE:FF`, the RFC 7042 documentation range `00:00:5E:00:53:xx` |
| `disclosure-public-ip` | an IPv4 literal | private (RFC 1918), loopback, link-local, CGNAT (`100.64.0.0/10`), the three documentation ranges, `0/8`, `224/4` and above (multicast, reserved, netmasks) and the public DNS resolvers of Cloudflare, Google and Quad9 |
| `disclosure-serial` | `serial`, `serial number`, `S/N`, `SN` or `service tag` followed by `:`, `=`, `#` or `\|` and a value of six or more characters with a digit | a keyword with a short or digit-less value (`serial: 1`, `serial: pending`) |

The exceptions are, in this order of preference:

1. **Write a placeholder** instead: a documentation range or `example.com`.
2. **A marker on the line**, `disclosure:allow` after a `#` or in an HTML comment, for a value that must stay and is not personal. The marker sits next to what it excuses and shows up in review.
3. **A file `exclude` of the hook** in `.pre-commit-config.yaml`, for text that is not ours: every hook skips `vendor/` (upstream manifests, byte-identical to upstream by the [vendoring check](kustomize.md#vendored-upstream-manifests)), the IP hook also `*.svg` (path data) and `*.lock`. The email hook also skips the `prod` `ClusterIssuer` of the cert-manager unit until its contact address is settled ([#2288](https://github.com/isejalabs/homelab/issues/2288)); drop that exclude when that issue closes.

What the patterns cannot see: IPv6 addresses, MAC addresses in dotted (`aaaa.bbbb.cccc`) or unseparated form, names, postal addresses and anything that is not a class. Those are what the private list is for. A pattern hit is a candidate, not a verdict: classify it by [ADR 0019](../decisions/0019-public-disclosure-policy.md) and fix the file, not the pattern.

### Private term list (local only)

`disclosure-private-terms` ([`scripts/tools/check-private-terms.sh`](../../scripts/tools/check-private-terms.sh)) fails when a changed file contains a term from a list that lives outside the repository. It is a no-op with the message `skipped, no private term list configured` when no list exists, which is the case in CI and for anyone who is not the owner.

- **Where**: the path in `DISCLOSURE_TERMS_FILE`, else `${XDG_CONFIG_HOME:-~/.config}/homelab/disclosure-terms.tsv`. Keep the master copy in the private vault ([ADR 0019](../decisions/0019-public-disclosure-policy.md#private-records-and-enforcement)); the file on the disk is a local copy.
- **Format**: tab-separated, one entry per line: `category`, `kind` (`literal` or `regex`), `term`. The term is matched case-insensitively and as a whole word; a `regex` is an extended regular expression. The category is a label for the owner only, `#` lines (the first row documents the format) and blank lines are ignored, and a line with a single column counts as a literal term. 
- **Output**: only `file:line` and that the file contains a term, never the term, the regex or the line, so a failing run can be pasted into an issue. A regex that does not compile fails the hook with its entry number only.
- **By hand, over the whole tree**: `scripts/tools/check-private-terms.sh --all`.

The hook reads files, not commit messages, branch names or the text of issues and pull requests. Those are checked by hand with the same script, which takes any file, not only tracked ones: write the text to a file, run `scripts/tools/check-private-terms.sh <file>` and publish that same file (`gh issue create --body-file <file>`, `gh pr create --body-file <file>`, `git commit -F <file>`); for the commits of a branch, `git log --format=%B origin/main..HEAD > <file>` first. Do not grep the list directly: the format has three columns and a plain `grep` prints the matching line, which puts the term into the output. [`AGENTS.md`](../../AGENTS.md) makes this step mandatory for agents before they publish text, because a session that skipped it published a term in an issue body ([#2332](https://github.com/isejalabs/homelab/issues/2332)). A Claude Code `PreToolUse` hook, [`scripts/agent/disclosure-pre-publish.py`](../../scripts/agent/disclosure-pre-publish.py) (wired in [`.claude/settings.json`](../../.claude/settings.json)), enforces it: it blocks a `gh issue|pr|release|discussion` write command, a `gh api` call and `git commit`/`git tag` whose text, or `--body-file`/`--notes-file`/`-F`/`--file` file, hits the list, and names where, never the term. It is a no-op without a list and only warns when the list is unusable. It sees the command text only, so a body assembled from a variable or a command substitution of a file is checked only through the explicit file option, and it does not run in Codex sessions. Existing issue and pull request text is covered by the sweep of [#2285](https://github.com/isejalabs/homelab/issues/2285).

### Tests and running it

[`scripts/ci/test-disclosure-hooks.sh`](../../scripts/ci/test-disclosure-hooks.sh) runs in the `pre-commit` workflow: in a scratch repository it seeds one violation per class, expects the hook to fail on it, and expects the allowlisted values and the marker to pass. The seeded values are synthetic (a benchmarking-range address, a never-delegated TLD, a locally administered MAC) and assembled from parts, so the repository holds no real string, not even in the test. The same script covers the private hook with a synthetic term in a temporary list.

Run one hook over everything with `pre-commit run disclosure-public-ip --all-files`, or all with `pre-commit run --all-files`.

### Why not an existing scanner

Looked at before writing it (full record in the pull request that introduced it): `gitleaks` (custom rules in TOML, per-rule allowlists, but its pre-commit hook scans only staged changes, so CI would need its own run, a new pinned binary and a separate required check), `trufflehog` (custom regex detectors are alpha and built around verifying secrets), `detect-secrets` (custom plugins are Python code; last release 2024), `semgrep` (a heavy tool for four regexes), and PII scanners (`pdscan`, `pii-scan`, Presidio-based ones, a hosted-API pre-commit hook; they target data stores or need ML or a remote service). `pygrep` needs nothing the `pre-commit` workflow does not already run.

## Docs checks that don't block a PR

The required `docs-link-check` stays offline on purpose. Two further checks cover what it leaves out, and neither is in `main`'s required-check list.

### External link check (scheduled)

[`docs-link-check-external.yml`](../../.github/workflows/docs-link-check-external.yml) runs `lychee` online (http and https URLs only, `lychee` pinned in [`.mise.toml`](../../.mise.toml) like the offline check) every Monday and on `workflow_dispatch`. It has no `pull_request` trigger, so a dead URL cannot block a merge.

It keeps exactly one tracking issue, titled `docs: external links in the documentation are dead`, found by that title among the open issues:

- Broken links and no open issue: it opens one (label `documentation`) with the `lychee` report.
- Broken links and an open issue: it replaces the issue body with the new report.

Each broken link is a task list item (`- [ ] ...`), so single items can be converted to sub-issues by hand with GitHub's "Convert to sub-issue"; nothing is converted automatically. Converting an item removes its line from the body, and every run rewrites the body, so a link that is still broken would come back as a new item. To avoid a duplicate, an item is left out while an open sub-issue of the tracking issue has its URL in the title (the URL is written without the angle brackets `lychee` prints, which GitHub would drop from the title). Close a sub-issue and the link is listed again if it is still broken; a link you don't want checked belongs in the excludes of the workflow instead.
- No broken link and an open issue: it closes the issue with a comment.

HTTP 429 counts as alive (a rate limit says nothing about the link); the `iseja.net` hosts, `localhost` and the `example.com`/`example.org` placeholders are excluded, as is the private repository `sebiklamar/salt-iseja.net`, which the workflow token can't read, so its links would always look dead. `_attic` and `ZZ.bak` are skipped as retired material, and so is `docs/audits`: audits are never edited after the fact ([`docs/audits/README.md`](../audits/README.md)), so a dead URL there can't be fixed. The offline check still covers the audits. The exit codes 0 and 2 of `lychee` are handled; any other exit code fails the job, which is the signal that the check itself broke. To run it by hand: `gh workflow run docs-link-check-external.yml`.

### Spell check (advisory)

[`spell-check.yml`](../../.github/workflows/spell-check.yml) runs [`typos`](https://github.com/crate-ci/typos) over every tracked `*.md` file on pull requests and pushes that touch Markdown, the config or the workflow itself. It is not a required check, so a hit shows red on the PR and blocks nothing. Promote it to required (and update the lists in this file and in [`AGENTS.md`](../../AGENTS.md)) only after it has stayed quiet for a while.

- **Project dictionary and exclusions**: [`.ci/typos/typos.toml`](../../.ci/typos/typos.toml). `extend-words` holds words `typos` would otherwise "correct" (today `flate`, the Flux validation tool, and `RTO`). `extend-exclude` skips `docs/audits/` (never edited after the fact), `_attic/`, `ZZ.bak/`, the `.commons` submodule and sops files. Add a word to `extend-words` instead of rewording a document to please the check.
- **Version**: pinned in the workflow (`typos==1.51.1` through `pipx run`), not in `.mise.toml`. A tool added there needs `mise.lock` checksums and is installed by every workflow that runs `mise-action` without `install_args`, for a check that only this workflow uses.
- **Run it locally**: `git ls-files -z '*.md' | xargs -0 pipx run --spec typos==1.51.1 typos --config .ci/typos/typos.toml --force-exclude --format brief`.
- **What it does not catch**: `typos` flags known misspellings, it does not check against a full dictionary and it does not read grammar. A word that is a misspelling of nothing known (such as `whigh` in `k8s/bootstrap/README.md`) or a dropped letter that leaves a valid word (`t is the law`) passes. A full-dictionary checker would catch the first, but it flagged about 270 words of this repo's vocabulary (Kubernetes kinds, tool and host names) even with inline code ignored, so it was not adopted.

### Script lint (advisory)

The `script-lint` job of [`pre-commit.yml`](../../.github/workflows/pre-commit.yml) runs two hooks of [`.pre-commit-config.yaml`](../../.pre-commit-config.yaml) over all files: `shellcheck` for the shell scripts and `just-fmt` (`just --fmt --check`) for `.justfile` and the `*.just` modules. Both hooks are in the `manual` stage, so neither `git commit` nor the required `pre-commit` job runs them, and the job is its own status check, which is not required: a hit shows red on the PR and blocks nothing. To make them binding, remove `stages: [manual]` from the two hooks (the required `pre-commit` job then runs them and the `script-lint` job can go); that is a decision for the repository owner.

- **Run it locally**: `pre-commit run --hook-stage manual shellcheck --all-files` and `pre-commit run --hook-stage manual just-fmt --all-files`. Fix a formatting hit with `just --fmt --justfile <file>`.
- **`shellcheck` scope and settings**: every file `pre-commit` identifies as shell (by extension or shebang), except the two classes in the hook's `exclude`: a script template that is not plain shell, and the `.envrc` files. [`.shellcheckrc`](../../.shellcheckrc) makes it follow sourced files (`scripts/lib/*.sh`) and disables two codes repo-wide that only flag intended idioms here, with the reason next to each. Anything else is silenced where it occurs, with `# shellcheck disable=SC<n> # <reason>` on the line above.
- **Versions**: `shellcheck` comes from the [`shellcheck-py`](https://github.com/shellcheck-py/shellcheck-py) hook, which brings its own binary, so the version is the hook's `rev` and nothing is added to `.mise.toml`. `just` is the one pinned in [`.mise.toml`](../../.mise.toml); the formatter's output can change between `just` versions, so a `just` update may need a `just --fmt` pass in the same PR.

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
