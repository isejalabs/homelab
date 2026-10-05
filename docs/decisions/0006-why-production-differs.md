# Why production differs from the other environments

## Status

current

## Context

All [8 environments](0005-eight-environments.md) share the same kustomize/Terragrunt structure (see [ADR 0004](0004-kustomize-overlays.md), [ADR 0003](0003-terragrunt.md)), but `prod` carries real consequences none of the others do — actual data, actual availability, nothing to fall back to if it breaks. That asymmetry shows up as several concrete, deliberate differences rather than one single policy.

## Options considered

- **Treat every environment identically** (rejected) — would mean `prod` gets the same change-application freedom as `dev`/`poc`, which doesn't match the actual risk difference: a bad Terragrunt/Tofu change is cluster-infrastructure-level (nodes, CNI, control plane), not scoped to one app's Flux `Kustomization`.
- **Differentiate `prod` along specific, enforced axes (chosen)** — each difference below targets a specific real risk rather than a generic "be more careful."

## Decision

`prod` differs from every other environment along these specific axes (see [`environments.md`](../architecture/environments.md#what-each-environment-is-for) for the authoritative current-state detail):

- **Topology**: the only full 3-controlplane HA setup (vs. 1 controlplane elsewhere, including `rebuild`'s otherwise-identical sizing).
- **Version pinning**: its own separately pinned Talos/Kubernetes version, validated in `qa` first rather than following `head`/`main` directly.
- **No branch-tracking override**: excluded from the [`track-branch`](../../.agents/skills/track-branch/SKILL.md) skill's live-cluster testing entirely — baked into the manifests themselves (no commented-out `ref:` placeholder in its `flux-instance` overlay), not just convention.
- **`main`-checkout-only Terragrunt applies**: `prod` and `qa` may only ever be `terragrunt apply`'d from a `main` checkout, never a feature branch — unlike Flux config (revertible by pointing back at `main`), a Terragrunt apply from a branch creates real state that only matches that unmerged branch.
- **Real domain, no prefix**: the unprefixed `iseja.net`-style domain, where every other environment gets an env-prefixed one.
- **`qa` as the gate immediately before it**: changes get exercised in `qa` (full app+infra set, same `main`-only Terragrunt restriction) before being considered safe for `prod`.

## Consequences

- `prod`-specific risk (HA topology, independent version pinning, stricter apply rules) is enforced structurally (manifest shape, branch-protection-equivalent convention) rather than relying on operator discipline alone.
- Any change to how environments are provisioned/reconciled has to account for `prod` *and* `qa` needing the stricter `main`-only Terragrunt rule, while the other 6 environments don't.
- A `prod`-only version-pinning bug can't be caught by `head`/`dev` alone, since they deliberately don't mirror `prod`'s own pin — `qa` validating the exact version destined for `prod` is what actually covers this gap.
