# Multiple environments, and why production differs from the rest

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

`prod` carries real consequences none of the others do — actual data, actual availability, nothing to fall back to if it breaks. That asymmetry shows up as several concrete, deliberate differences from every other environment, not one single policy.

## Options considered

- **A single fixed environment count, designed upfront (rejected implicitly)** — not how this actually happened; each environment was added when a distinct, unmet need showed up. The alternative rejected at each step was reusing an existing environment for a new, conflicting purpose instead of adding a new one (e.g. debugging inside `dev`, bleeding-edge testing inside `prod`/`qa`).
- **Treat every environment identically (rejected)** — would give `prod` the same change-application freedom as `dev`/`poc`, which doesn't match the actual risk difference: a bad Terragrunt/Tofu change is cluster-infrastructure-level (nodes, CNI, control plane), not scoped to one app's Flux `Kustomization`.
- **Differentiate `prod` along specific, enforced axes (chosen)** — each difference below targets a specific real risk rather than a generic "be more careful."

## Decision

Keep 8 distinct environments, each scoped to one purpose per [`environments.md`](../architecture/environments.md), composed uniformly via kustomize overlays (see [ADR 0004](0004-kustomize-overlays.md)) and Terragrunt units (see [ADR 0003](0003-terragrunt.md)).

`prod` differs from every other environment along these specific, enforced axes (see [`environments.md`](../architecture/environments.md#what-each-environment-is-for) and [`reference/environments.md`](../reference/environments.md) for the authoritative current-state detail):

- **Topology**: the only full 3-controlplane HA setup (vs. 1 controlplane everywhere else, including `qa` and `rebuild`).
- **Version pinning**: its own separately pinned Talos/Kubernetes version, validated in `qa` first rather than following `head`/`main` directly.
- **No branch-tracking override**: excluded from the [`track-branch`](../../.agents/skills/track-branch/SKILL.md) skill's live-cluster testing entirely — baked into the manifests themselves (no commented-out `ref:` placeholder in its `flux-instance` overlay), not just convention.
- **`main`-checkout-only Terragrunt applies**: `prod` and `qa` may only ever be `terragrunt apply`'d from a `main` checkout, never a feature branch — unlike Flux config (revertible by pointing back at `main`), a Terragrunt apply from a branch creates real state that only matches that unmerged branch.
- **Real domain, no prefix**: the unprefixed `iseja.net`-style domain, where every other environment gets an env-prefixed one.
- **`qa` as the gate immediately before it**: changes get exercised in `qa` (full app+infra set, same `main`-only Terragrunt restriction) before being considered safe for `prod`.

## Consequences

- A new concern (e.g. a separate debugging track) gets a new environment rather than overloading an existing one's purpose — keeps each environment's role legible, at the cost of more Terragrunt units/kustomize overlays to maintain in parallel.
- `prod`-specific risk (HA topology, independent version pinning, stricter apply rules) is enforced structurally (manifest shape, branch-protection-equivalent convention) rather than relying on operator discipline alone.
- A `prod`-only version-pinning bug can't be caught by `head`/`dev` alone, since they deliberately don't mirror `prod`'s own pin — `qa` validating the exact version destined for `prod` is what actually covers this gap.
- **Neither `qa` nor `rebuild` runs a 3-controlplane HA topology** (both 1+3, per [`reference/environments.md`](../reference/environments.md#per-environment-resource-sizing-terragrunt)) — an HA-specific control-plane issue (e.g. etcd quorum behavior, a leader-election edge case) can't be caught by either pre-prod environment, only in `prod` itself. This is an accepted gap, not an oversight: full HA costs more per non-prod environment than the risk has justified paying for so far.

`qa` and `rebuild` are sized identically to each other — both differ from `prod` only by a smaller worker disk size, not from one another. Not relevant to this decision either way, noted here only to correct an earlier draft of this ADR that assumed otherwise.

## Open decisions

- Whether "how a change gets validated before landing in `prod`" (the `dev`→`qa`→`prod` promotion flow, what actually gets tested at each stage) deserves its own write-up. This reads more like an operational process/workflow than a structural "which option and why" decision, so it likely belongs as an expansion of `environments.md` or a new top-level procedural doc rather than a new ADR — not decided here, flagging for a separate call.
