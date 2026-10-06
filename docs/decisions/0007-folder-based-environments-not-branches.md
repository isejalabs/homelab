# Folder-based environment separation, not git branches

## Status

current

## Context

Both axes that need per-environment separation — Terragrunt (see [ADR 0003](0003-terragrunt.md)) and kustomize overlays (see [ADR 0004](0004-kustomize-overlays.md)) — solve it with directory structure inside one branch, not with a git branch, fork, tag, or other ref per environment. All environments normally target `main` — there's no per-environment git branch or fork at all (see [`environments.md`](../architecture/environments.md)'s own opening statement of this). The one deliberate, explicitly temporary exception is the [`track-branch`](../../.agents/skills/track-branch/SKILL.md) skill, which points a single non-prod environment's Flux instance at a feature branch to test an unmerged change live — always reverted once testing is done, never a standing per-environment branch.

The two tools apply this principle with a different base footprint: kustomize's `base/` is itself the full, shared resource definition that every environment's `envs/<env>/` overlay patches (see [ADR 0004](0004-kustomize-overlays.md)); Terragrunt's equivalent sharing is thinner — mostly the module `source` reference plus `_envcommon/*.hcl` includes, with more per-environment surface area actually duplicated in each `terragrunt.hcl` than kustomize leaves in an `envs/<env>/` overlay.

## Options considered

- **A git branch per environment (rejected)** — the classic anti-pattern this decision avoids: merge/drift hell keeping N branches in sync, and no single branch ever reflecting the whole system's deployable truth at once.
- **Folder/overlay-based separation within one branch (chosen)** — every environment's config is just a path under `main`; a PR changing multiple environments is an ordinary PR, not a cross-branch merge.

## Decision

Every environment's Terragrunt units and kustomize overlays live under `main`, differentiated by folder path, never by git ref. A feature branch may *temporarily* override one environment's tracked ref for live testing (`track-branch`), but that's explicitly throwaway and reverted before merge — not a second standing mechanism alongside the folder-based one.

## Consequences

- `main` always reflects deployable truth for every environment simultaneously (modulo each environment's own Flux reconciliation lag) — there's no environment whose current intended state can only be found by checking out a different branch.
- Reviewing a change that spans multiple environments is a normal PR diff, not a multi-branch merge coordination problem.
- The `track-branch` skill's override is explicitly documented as temporary and self-reverting specifically because the standing model is branch-free — it would be a much bigger exception if branches-per-environment were ever the norm instead of a deliberate, narrow carve-out.
