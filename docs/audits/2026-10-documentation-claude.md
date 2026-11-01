# Documentation Audit — October 2026, second pass (structure, presentation and publishing)

**Date:** 2026-10-31. **Status:** Assessment complete; six follow-up issues created beneath [#1336](https://github.com/isejalabs/homelab/issues/1336), one or more per finding (see [Follow-up issues](#follow-up-issues)). **Scope:** Documentation structure, navigation, readability, accuracy of entry points, diagrams, tooling and publishing, compared with the approach of [mitchross/talos-argocd-proxmox](https://github.com/mitchross/talos-argocd-proxmox). Explicitly not covered: the content of individual runbooks (not re-tested), public disclosure (owned by [#1601](https://github.com/isejalabs/homelab/issues/1601)), recovery gaps ([#1600](https://github.com/isejalabs/homelab/issues/1600)). **Origin:** Claude Code, read-only review of the `main` checkout plus the public reference repository. **Tracking:** Related to the [Documentation improvement journey](https://github.com/isejalabs/homelab/issues/1336); complements, and deliberately does not repeat, the [first October pass](2026-10-documentation.md).

## Summary

The documentation system is already well above typical homelab practice. What it lacks is presentation, not discipline: everything is plain Markdown on github.com, every diagram is ASCII, there is no search or sidebar, and a few hand-maintained entry points have drifted from the code. The recommendations are therefore ordered by value for effort:

1. Fix the factual drift in entry points (S3), and stop it recurring by deriving or removing hand-maintained counts.
2. Publish a site ([S1](#s1--publish-the-documentation-as-a-github-pages-site)) and add real diagrams ([S2](#s2--replace-ascii-flow-diagrams-with-mermaid-and-add-a-hero-svg)).
3. Reduce duplication between the several "what is in this repo" descriptions (S4) and flatten-by-grouping `docs/` (S5).
4. Close content gaps for a first-time reader (S6), tighten automation (S7) and readability (S8).

## What already works well

These are worth keeping and are the reason most recommendations below are additive:

- A clear taxonomy with an explicit rule for where a new doc belongs (`docs/README.md`), and colocated per-folder READMEs so docs change in the same PR as the code.
- Status labelling (`current`/`planning`/`historical`/`audit`) in front matter, plus ADRs with their own status, so a reader can tell authoritative from historical.
- Task-first tables ("I need to…") on both the root README and `docs/README.md`, and "Common tasks" / "On this page" jump lines at the top of the long Terragrunt README.
- Verification built in: `docs-link-check` runs `lychee` with `--include-fragments` on every PR, the PR template has a documentation checkbox, and the `doc-gap-check` skill is deliberately report-only.
- Honest scoping: the disaster-recovery guide separates cluster recovery from whole-homelab recovery and says what was and was not exercised.

## Comparison with the reference repository

What the reference does that this repo does not, and whether it is worth adopting:

| Reference practice | Here today | Verdict |
| --- | --- | --- |
| MkDocs Material site on GitHub Pages, built `--strict` in CI | Markdown on github.com only | Adopt ([S1](#s1--publish-the-documentation-as-a-github-pages-site)) |
| Animated hero SVG (SMIL packets, reduced-motion fallback) | No images at all | Adopt, and improve with dark mode and no font dependency ([S2](#s2--replace-ascii-flow-diagrams-with-mermaid-and-add-a-hero-svg)) |
| Mermaid via a superfences fence | None in the repo | Adopt ([S2](#s2--replace-ascii-flow-diagrams-with-mermaid-and-add-a-hero-svg)) |
| Sync-wave table in the README | The Flux `sets/` model is explained across several docs, not in one table or picture | Adopt as a diagram and short table in the overview |
| Glossary, getting-started guide, "documentation standard" page | `docs/README.md` conventions exist; no glossary or getting-started page | Partly adopt (S6) |
| Hardware section in the README | None | Optional; gated on [#1601](https://github.com/isejalabs/homelab/issues/1601) |
| `llms.txt` at the root | `AGENTS.md` only | Optional and low value; skip unless a site exists |
| Edit-this-page links, copy buttons, search | Not available on github.com | Come with S1 |

Limits of this comparison: the Pages site itself could not be opened from the review environment (the host was outside the allowed network), so everything above about the reference comes from its repository files (`mkdocs.yml`, the docs workflow and the SVG source), not from looking at the rendered result.

## Findings and recommendations

### S1 — Publish the documentation as a GitHub Pages site

**Priority:** High value, medium effort. The repository has 20 top-level procedure docs, 11 architecture docs, 16 ADRs, reference tables, audits, plans and per-folder READMEs, navigated through four hand-maintained index tables. There is no search and no sidebar. The reference repo's biggest usability gain is its site: search, a grouped sidebar, dark mode, copy buttons.

**Recommendation:** Tracked in [#2027](https://github.com/isejalabs/homelab/issues/2027). The non-obvious work, which the issue spells out, is not the theme but three repo-specific constraints: colocated READMEs live outside `docs/` and must be included without moving them; links from docs to source files and directories must be rewritten to GitHub URLs on the site while staying relative on github.com (so `docs-link-check` keeps working); and the site makes the disclosure question in [#1601](https://github.com/isejalabs/homelab/issues/1601) more pressing. Also worth a short check before committing: the generator choice, because Material for MkDocs has been announced to enter maintenance mode.

### S2 — Replace ASCII flow diagrams with Mermaid and add a hero SVG

**Priority:** High value, medium effort. There are roughly 220 lines of box-drawing characters in 10 Markdown files, and no image or Mermaid block anywhere. Most of those lines are directory trees, which are fine as text. The genuine diagrams are few (the stack in `docs/architecture/overview.md`, the overlay composition in `docs/architecture/kustomize.md`) while several mechanisms are explained only in prose: bootstrap sequence, environment promotion, DNS path, secrets flow, backup flow, CI pipeline and the rebuild checkpoints.

**Recommendation:** Tracked in [#2028](https://github.com/isejalabs/homelab/issues/2028): one animated hero SVG on the root README, Mermaid for eight prioritised flows, written conventions for when to draw, and a validity check, since GitHub renders broken Mermaid as an error box instead of failing anything. It does not depend on S1.

### S3 — Entry points have drifted from the code

**Priority:** High, small effort. Hand-maintained facts in entry-point docs disagree with the repository. Verified on 2026-10-31:

- `docs/architecture/workloads.md` says every environment gets "the three **minimal** apps" and the others "the six **optional** ones". `k8s/bootstrap/cluster/flux/sets/apps/minimal/kustomization.yaml` lists four units (`whoami`, `powerdns`, `checkmk-agent`, `metrics-server`) and `sets/apps/optional/kustomization.yaml` lists five (`adguard`, `unbound`, `actualbudget`, `unifi-controller`, `unifi-mongodb`). The same page's own table has four rows marked minimal.
- `k8s/README.md` and `AGENTS.md` describe the Flux sets as "`infra`/`apps` × `minimal`/`optional`". The directory also contains `sets/minimal` and `sets/soaking` (documented in `environments.md`, but not here). `k8s/README.md`'s `apps/` tree also omits `home-automation` and `identity`.
- The root `README.md` says `AGENTS.md` is "symlinked as `CLAUDE.md`". `CLAUDE.md` is a regular 158-byte file whose body has a typo ("t is the law here"). `.commons/README.md` also describes a symlink as the convention.
- `k8s/bootstrap/README.md` line 75: "whigh".

The cause is the same each time: a number or list was written by hand in prose, and the code moved on. `workloads.md` already states that its columns are "checkable against the repo, not editorial judgment", which is exactly what makes them automatable.

**Recommendation:** Fix the four items now. Then remove numeric counts from prose where a link to the table suffices ("the minimal apps, listed below"), and add a small script, run by the existing CI pattern, that compares the `workloads.md` table with the `sets/*/kustomization.yaml` contents. A check like this is cheaper and more reliable than another audit. Decide once whether `CLAUDE.md` is a symlink (what the README and commons say) or a stub (what it is); then make the README true.

### S4 — The same repository map is written in several places

**Priority:** Medium. "What is in this repo" exists as the root README's "Folder structure" block, `AGENTS.md`'s "Repository layout" section (long, dense paragraphs), `k8s/README.md`'s tree, and `docs/README.md`'s per-file bullet list under "What goes where". The root README even recommends `AGENTS.md` as "a decent map of the layout for humans". Each copy drifts independently (S3 is the symptom); the root tree also omits `.codex/` and `.vscode/` although they exist.

**Recommendation:** Pick one authoritative description per level and link between them: root tree = top-level folders only; `k8s/README.md` = the `k8s` tree; `docs/README.md` = taxonomy and rules, with the file inventory left to the generated or sidebar navigation rather than a second hand-written list. Keep `AGENTS.md` for agent rules and commands, and let humans start from the README. This also reduces what an agent must load every session.

### S5 — `docs/` is flat and grouped by file-name prefix

**Priority:** Medium. `docs/` holds 20 top-level files besides its `README.md` that cluster by name: four `troubleshooting-*`, four `keycloak-*`, three `proxmox-*`, plus backup, upgrade and lifecycle runbooks. `docs/README.md` compensates with a hand-written table and a 20-bullet list. Separately, dated material (audits ≈2,200 lines, plans, raw install logs ≈860 lines) sits at the same level as current-state docs.

**Recommendation:** Group in navigation first (the S1 site can present operations, backup and restore, identity, and troubleshooting without moving a file), and only then decide whether moving files into `docs/operations/`, `docs/identity/` etc. is worth the churn. `docs-link-check` makes a later move safe for internal links; external links to the old paths are the real cost. Keep audits, plans and logs in a clearly separate "history" section so a reader looking for current truth never lands in them by accident. Consider whether raw install logs belong in `docs/` at all.

### S6 — Gaps for a first-time reader

**Priority:** Medium. The documentation is written for its maintainer, which is a legitimate choice, but a reader arriving from the reference-repo community (the stated audience for borrowed material) will struggle with:

- **Vocabulary:** `kopiur`, `soaking`, `flate`, `head`/`poc`/`src`/`dbg`, "minimal/optional", "pet VM", "standing envs". There is no glossary page.
- **A prerequisites-and-versions view:** tools are pinned in `.mise.toml`, but there is no short "what you need installed" table in the README.
- **A numbered bootstrap path:** the pieces exist (`terragrunt/README.md`, `k8s/bootstrap/README.md`, `disaster-recovery.md`) but a single, short end-to-end sequence with expected outcomes at each step lives only inside the recovery guide.
- **A hardware/inventory summary,** which the reference repo's README has. Gated on the disclosure decision in [#1601](https://github.com/isejalabs/homelab/issues/1601).

**Recommendation:** Add a `docs/glossary.md` (cheap and high value, and a natural fit for hover tooltips on a site), a prerequisites table in the root README linking to `.mise.toml`, and a short "From zero to a running cluster" page that links to the owning docs rather than copying steps. Decide the hardware summary after #1601.

### S7 — Documentation automation has two obvious holes

**Priority:** Low to medium. `docs-link-check` is offline-only by deliberate choice (rate limits and flakiness, see [#1349](https://github.com/isejalabs/homelab/issues/1349)), so external links are never checked: the 356 distinct URLs in the docs can rot silently. There is also no prose or Markdown linting, which is how typos like the ones in S3 survive.

**Recommendation:** Keep the PR check offline, and add a scheduled (for example weekly) online `lychee` run that opens or updates a single tracking issue instead of failing PRs. Add a spell check with a project dictionary and, if wanted, `markdownlint` with a small rule set that matches existing conventions. Both are advisory first; promote them to required checks only if they prove quiet.

### S8 — Readability is dense in the longest paragraphs

**Priority:** Low to medium. Many paragraphs in the root README, `AGENTS.md` and the runbooks run 150–250 words with nested parentheses and em-dash asides (for example the first "Principles" bullet, "Staying current", and the "Apply from `main`" paragraph in `AGENTS.md`). The content is precise, but the answer is often buried behind the caveats.

**Recommendation:** Lead with the rule, then the reason. Use GitHub's native alerts (`> [!NOTE]`, `> [!WARNING]`, `> [!CAUTION]`) in runbooks for destructive or order-sensitive steps; they render on github.com today and map to admonitions on a MkDocs site. Give runbooks a consistent skeleton (when to use, prerequisites, steps with expected output, verify, rollback, last exercised); the recovery guide is already close and can be the template. Break out any bullet longer than about three sentences into a short sub-list or a linked section. Fix the root README's opening line under the DeepWiki badge, which currently begins with a badge as the grammatical subject.

## Follow-up issues

All six are native sub-issues of the existing [Documentation improvement journey](https://github.com/isejalabs/homelab/issues/1336). Each is small and self-contained, so none needs an intermediate umbrella:

| Finding | Issue |
| --- | --- |
| S1 — GitHub Pages site | [#2027](https://github.com/isejalabs/homelab/issues/2027) |
| S2 — Mermaid diagrams and hero SVG | [#2028](https://github.com/isejalabs/homelab/issues/2028) |
| S3 — drifted entry-point facts and a catalog check | [#2029](https://github.com/isejalabs/homelab/issues/2029) |
| S4, S5 — single repository map, grouping of `docs/` | [#2030](https://github.com/isejalabs/homelab/issues/2030) |
| S6 — glossary, prerequisites, zero-to-cluster page | [#2031](https://github.com/isejalabs/homelab/issues/2031) |
| S7, S8 — scheduled link check, spell check, runbook skeleton | [#2032](https://github.com/isejalabs/homelab/issues/2032) |

## Review method and limits

Read-only review of the local checkout at the commit current on 2026-10-31, the public reference repository's files, and the existing issue tracker (to avoid duplicates; no existing issue covers a Pages site or diagrams). Counts (lines, files, URLs) were taken from the working tree with simple scripts and are indicative. Procedures were not re-tested, external links were not re-verified, and the reference site was not viewed rendered. The claim about Material for MkDocs entering maintenance mode comes from the model's background knowledge, not from a source checked during this review, and should be confirmed before the tool decision in [#2027](https://github.com/isejalabs/homelab/issues/2027).
