# Helm usage: kept independent of kustomize, and of Flux's own value-composition features

## Status

planning

## Context

Helm and kustomize are treated as independent, orthogonal choices in this repo rather than competing — kustomize overlays own the environment-variation axis for everything Flux reconciles (see [ADR 0004](0004-kustomize-overlays.md)), while Helm is used only where an app/component actually ships as a chart. Within that, two separate Helm-related choices needed their own rationale, distinct from the kustomize-overlays decision:

1. **Cilium's values are sourced differently from a standard chart-based app.** Every other Helm-based app (wrapped in a Flux `HelmRelease`) gets its values composed the normal way: a base `values:` block in `base/helmrelease.yaml`, patched per environment via a kustomize overlay, same as any other field. Cilium is installed earlier, during the one-time bootstrap `helmfile` stage (before Flux exists at all — see [`k8s/bootstrap/README.md`](../../k8s/bootstrap/README.md)), and its `helmfile.yaml.gotmpl` release instead `inherit`s values via a `values-from-helmrelease` template plus a separate `values-from-values-yaml-file` template, rather than a plain base-plus-overlay composition. *(Noting this as understood from reading the actual `helmfile.yaml.gotmpl` — flagging for confirmation that this is the right characterization of the underlying constraint, rather than asserting it as settled.)*
2. **Helm values are always committed as plain YAML, never Flux's own `valuesFrom`-style runtime composition.** Deliberately avoided from the start, for the same reason ArgoCD's native Helm-repository integration was avoided (see [ADR 0009](0009-flux-vs-argocd.md)): staying reconciliation-tool-agnostic rather than depending on a Flux-specific feature for something kustomize's own overlay/patch model already does perfectly well.

## Options considered

- **Let kustomize own Helm chart composition too, via `helmCharts:`/`helmChartInflationGenerator` (rejected as a universal default)** — kustomize's own docs are explicit this is a deliberately limited subset of Helm's feature set, never intended to be first-class (see [ADR 0009](0009-flux-vs-argocd.md)'s context section). Fine for simple cases, not relied on as the general mechanism here.
- **Flux's native values composition (`valuesFrom`, chart-level value merging) (rejected)** — would work, but creates a Flux-specific dependency in exactly the place this repo has otherwise avoided one.
- **Plain committed `values:` YAML, patched per environment via the same kustomize overlay mechanism as everything else (chosen)** — keeps Helm-based and plain-manifest apps on one consistent composition story.

## Decision

Helm chart values are written as plain YAML directly in each app's `base/helmrelease.yaml`, patched per environment through the normal kustomize overlay mechanism — not through Flux's own value-composition features. Cilium is the one exception, sourced through the bootstrap helmfile's own `values-from-helmrelease`/`values-from-values-yaml-file` templates instead, because it has to exist before Flux does.

## Consequences

- One consistent values-composition story for every Helm-based app except Cilium, keeping Helm orthogonal to the choice of reconciliation tool (Flux today, something else potentially later).
- Cilium's bootstrap-stage values sourcing is a documented, deliberate exception rather than an inconsistency nobody explained.
- Not leaning on kustomize's own Helm inflation generator for anything beyond the simplest cases avoids running into its documented upstream limitations later.

## Open decisions

- Confirm the precise technical reason Cilium's values can't use the same base-plus-overlay composition as a standard app — drafted here from reading `helmfile.yaml.gotmpl` directly, not yet confirmed against the owner's own understanding of the constraint.
