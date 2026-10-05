# Eight environments

## Status

current

## Context

The environment count grew from the original single PoC environment, one at a time, rather than being designed upfront — Terragrunt itself was adopted (see [ADR 0003](0003-terragrunt.md)) at the exact point a second environment was first added. Today there are 8: `dbg`, `dev`, `head`, `poc`, `prod`, `qa`, `rebuild`, `src` — each earning its place for a distinct reason rather than being an arbitrary round number (see [`environments.md`](../architecture/environments.md#what-each-environment-is-for) for the full per-environment rationale, not repeated here):

- `prod` — the real thing.
- `qa` — a validation gate before `prod`, since a bad Terragrunt/Tofu change is cluster-infrastructure-level risk, not just app-level.
- `head` — tracks the bleeding edge (newest Talos/Kubernetes, `ref=HEAD` module) to catch breakage early.
- `poc` — a throwaway testbed for bigger architectural experiments (e.g. the ArgoCD→Flux switch), deliberately separate from day-to-day work.
- `dev` — everyday feature development, typically tracking a feature branch rather than `main`.
- `dbg` — debugging/incident investigation, kept separate from `dev` so the two tracks don't collide.
- `rebuild` — exists purely to periodically rehearse disaster recovery from scratch.
- `src` — for developing the `terraform-proxmox-talos` module itself, against a local checkout.

## Options considered

Not a single upfront design choice between "N environments" options — each environment was added when a distinct, unmet need showed up (a validation gate before prod, a safe place for bleeding-edge testing, a separate debugging track, a disaster-recovery rehearsal, module development). The alternative implicitly rejected at each step was reusing an existing environment for a new, conflicting purpose instead of adding a new one (e.g. debugging inside `dev`, bleeding-edge testing inside `prod`/`qa`) — the "What each environment is for" rationale in `environments.md` is really a record of why each of those reuse-instead-of-add options was rejected one at a time.

## Decision

Keep 8 distinct environments, each scoped to one purpose per [`environments.md`](../architecture/environments.md), composed uniformly via kustomize overlays (see [ADR 0004](0004-kustomize-overlays.md)) and Terragrunt units (see [ADR 0003](0003-terragrunt.md)) rather than branching, forking, or hand-maintaining divergent configs.

## Consequences

- A new concern (e.g. a separate debugging track) gets a new environment rather than overloading an existing one's purpose — keeps each environment's role legible, at the cost of more Terragrunt units/kustomize overlays to maintain in parallel.
- Every environment shares the same overlay/unit structure, so adding environment 9 (should a new distinct need arise) is cheap relative to the original 1→2 jump that motivated adopting Terragrunt in the first place.
- Cost scales with environment count: 8 parallel Terragrunt units and kustomize overlay trees, 8 sets of per-environment secrets/credentials, and CI (`terragrunt-validate.yml`, `kustomize-build.yml`) validating all 8 on every relevant change.
