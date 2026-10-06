---
name: doc-gap-check
description: Report-only check for stale/missing documentation given a diff — cross-references changed files against the ownership convention (nearest README.md, plus docs/README.md's "What goes where" mapping) and lists candidates to look at. Never edits a doc itself; a flag is a candidate for a human/agent to judge, not a mandate. Supports the commons "Documentation check, once right before merge" convention.
---

# Check for documentation gaps in a diff

A narrow, prototype workflow for [issue #1351](https://github.com/isejalabs/homelab/issues/1351): catch the same class of miss as [isejalabs/homelab#1446](https://github.com/isejalabs/homelab/issues/1446) (new scripts shipped with no index entry, inconsistent doc coverage, caught only after merge) before a PR is declared mergeable, instead of after. This is a checklist generator, not an editor — see Guardrails below for what it deliberately doesn't do.

## 0. Resolve the diff to check

Default to the common case — about to declare the current PR's documentation check satisfied:

```sh
git diff --name-only HEAD
git status --porcelain | awk '/^\?\?/ {print $2}'   # untracked new files
```

If the request names a branch instead, diff it against `main`:

```sh
git diff --name-only "$(git merge-base main <branch>)"...<branch>
```

If it names a PR number instead of a local branch:

```sh
gh pr diff <n> --name-only
```

## 1. Drop noise

Discard any path under `.claude/worktrees/`, `.terragrunt-cache/`, a vendored `charts/` cache, `_attic/`, or `docs/logs/` — these are either local state, caches, or explicitly historical/non-authoritative, never a documentation gap.

## 2. Same-folder ownership check (generic)

For each remaining changed file, walk up to the nearest ancestor directory containing a `README.md` (stop at the repo root). If that `README.md` is itself already in the diff, no flag — it's being kept in sync in the same PR, per [`docs/README.md`](../../../docs/README.md#ownership)'s ownership rule. If it isn't, flag it:

```
- [ ] <nearest README.md> — not updated alongside <changed file>
```

## 3. Cross-cutting mapping

Some docs don't sit next to any single piece of code — they're the top-level `architecture/`/`reference`/procedural docs in [`docs/README.md`](../../../docs/README.md#what-goes-where)'s own tables. Check these regardless of whether step 2 already flagged something nearby, since a change can need an architecture-level update for reasons the nearest local `README.md` wouldn't catch. Starting set — extend it when a real miss is found, the same way #1446 was the precedent for this whole skill, rather than trying to enumerate every path up front:

| Changed path prefix | Candidate doc(s) |
| --- | --- |
| `.github/workflows/` | [`docs/architecture/ci.md`](../../../docs/architecture/ci.md) |
| `.github/labeler.yml`, `.github/mergify.yml` | `ci.md`'s "PR labeling and Mergify" section |
| `.github/renovate.json5` | [`docs/update-handling.md`](../../../docs/update-handling.md) |
| New or removed `terragrunt/**/terragrunt.hcl` unit | [`terragrunt/README.md`](../../../terragrunt/README.md), [`docs/reference/environments.md`](../../../docs/reference/environments.md), [`docs/architecture/environments.md`](../../../docs/architecture/environments.md) |
| New top-level component dir under `k8s/infra/` or `k8s/apps/` | [`docs/architecture/workloads.md`](../../../docs/architecture/workloads.md) |
| `k8s/apps/storage/pvc*/base/` | [`docs/app-storage.md`](../../../docs/app-storage.md) |
| `k8s/infra/gateway-api/**`, `k8s/infra/kube-system/cilium/**`, `k8s/apps/dns/**` | [`docs/architecture/network.md`](../../../docs/architecture/network.md) |
| `k8s/infra/sealed-secrets/**`, `k8s/infra/external-secrets/**` | [`docs/architecture/secrets.md`](../../../docs/architecture/secrets.md) |
| `k8s/infra/csi-proxmox/**`, Longhorn manifests | [`docs/architecture/storage.md`](../../../docs/architecture/storage.md) |

## 4. Report, don't edit

Print the combined flags as a plain checklist and stop. Nothing beyond that — no doc file gets written by this skill.

## Guardrails (why this stays narrow)

- **Report-only, always.** This never writes to a doc file; it only prints candidates. Acting on, dismissing, or drafting a fix for a flag is a human/agent judgment call afterward, not something this skill does itself.
- **False positives are expected and fine; false confidence is not.** A flagged file may well turn out to need no doc change at all — a typo fix, an internal refactor, a version bump. Over-flagging costs a glance-and-dismiss; under-flagging reproduces the exact failure (#1446) this skill exists to catch. When in doubt, flag it.
- **Never treat an AI-drafted doc update as authoritative.** If a flag leads to actually drafting new doc text afterward, verify every factual claim — file paths, commands, counts — against the current repository before it goes into a PR, the same standard already held for any Claude-written doc change in this repo.
- **On-demand only, not a gate.** Run this right before declaring a PR's documentation check satisfied (the existing commons convention), not as a required CI check or a scheduled job. [`docs-link-check.yml`](../../../.github/workflows/docs-link-check.yml) (`lychee`, see [#1349](https://github.com/isejalabs/homelab/issues/1349)) already covers mechanical link-rot as a real CI gate; this is a semantic supplement someone chooses to run, never a merge blocker on its own.
