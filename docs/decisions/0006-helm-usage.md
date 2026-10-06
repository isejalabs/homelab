# Helm usage: kept independent of kustomize, moved from tool-agnostic to Flux-native values

## Status

current

## Context

Helm and kustomize are independent, orthogonal choices in this repo, not competing — kustomize overlays own the environment-variation axis for everything Flux reconciles (see [ADR 0004](0004-kustomize-overlays.md)), while Helm is used only where an app/component actually ships as a chart. From the start, every Helm-based app's values were declarative YAML, never the `helm` CLI's imperative `--values`/`--set` flags, which were never used at all — consistent with this repo's broader no-snowflakes, everything-in-Git philosophy.

**Cilium is a deliberate, technically-forced exception**, not a stylistic one. Its values live in an actual `values.yaml` file, and the bootstrap `helmfile.yaml.gotmpl` release explicitly switches off the `values-from-helmrelease` template every other bootstrap-stage app uses, keeping only `values-from-values-yaml-file` — because Cilium is bootstrapped *twice*: once by the one-time Helmfile stage, and once earlier still, by the `terraform-proxmox-talos` module itself, which injects a Talos inline manifest built by reading that same `values.yaml` file path directly off disk and wrapping its contents in a `ConfigMap` (see [`talos/config.tf`](https://github.com/isejalabs/terraform-proxmox-talos/blob/ff748148c367a3244f9334a3032dd1fbd2f4217f/talos/config.tf#L25-L46)). Terraform has no way to extract values from a Kubernetes `HelmRelease` custom resource — it can only read a literal file — so Cilium's values have to exist as a real `values.yaml` on disk for both consumers to share.

For every other Helm-based app, the approach evolved. Initially there was only one Helm chart invocation in `base/`, consuming `values.yaml` directly — fine as long as no app needed per-environment variation. `checkmk-agent` was the first app that did. Defining the chart invocation separately in each of the 8 environments (Cilium's pattern) was rejected as not DRY. The path taken instead was kustomize's `HelmChartInflationGenerator` with its `valuesInline` field — not `valuesFile`, which isn't inherited across overlays at all (confirmed the hard way: see [isejalabs/homelab#647](https://github.com/isejalabs/homelab/issues/647)'s own working example, `## do not use valuesFile as it's not inherited in overlays` / `## only inline values are inherited in overlays`) — letting a base values definition be extended per environment via ordinary strategic-merge. Git history shows a well-implemented variation of this, inspired by [@wmiller112's demo](https://github.com/wmiller112/kustomize-helm-values): a 2-level `generators:` indirection, where an environment overlay's `generators:` block points at its own small helm folder that itself extends the base `HelmChartInflationGenerator`.

That approach was eventually abandoned for most apps. Two things drove it: real limitations of Helm support inside kustomize encountered firsthand (`#647` above is one — a namespace-misdirection bug found while evaluating `openebs`, which was never actually adopted into this repo as a result), and no credible long-term plan from kustomize upstream for fixing Helm support generally ([kubernetes-sigs/kustomize#4401](https://redirect.github.com/kubernetes-sigs/kustomize/issues/4401), "Helm support: long term plan"). The conclusion: staying reconciliation/tool-agnostic for Helm values specifically wasn't worth its real, recurring cost once a genuinely tool-specific alternative (Flux's own `HelmRelease.spec.values:`) worked better — the same tradeoff already made for the GitOps controller itself (see [ADR 0009](0009-flux-vs-argocd.md)).

## Options considered

- **A separate Helm chart invocation per environment (rejected for non-Cilium apps)** — not DRY; this is Cilium's pattern today only because the Terraform double-bootstrap constraint leaves no other option.
- **kustomize `HelmChartInflationGenerator` + `valuesInline`, with a 2-level `generators:` composition for per-environment overrides (tried, later abandoned for most apps)** — worked, but hit real upstream limitations (`#647`) with no credible long-term fix in sight (`kustomize#4401`).
- **Flux-native `HelmRelease.spec.values:`, patched per environment via ordinary kustomize overlay patches (chosen for standard apps)** — the same uniform overlay treatment as any other resource (per [ADR 0004](0004-kustomize-overlays.md)), just with values living directly on the `HelmRelease` CR instead of being generated through kustomize's own Helm plugin.

## Decision

- Every Helm-based app's values are committed, declarative YAML — never the `helm` CLI's imperative flags.
- Cilium keeps its values in a real `values.yaml` file, consumed by both the bootstrap Helmfile stage (`values-from-values-yaml-file` only, deliberately not `values-from-helmrelease`) and the `terraform-proxmox-talos` module's own inline-manifest bootstrap — a forced exception, not a stylistic one.
- Every other Helm-based app's values live directly in its `base/helmrelease.yaml`'s `spec.values:` block, patched per environment through the normal kustomize overlay mechanism — not through kustomize's `HelmChartInflationGenerator`/`valuesInline`.

## Consequences

- Cilium's bootstrap-stage values sourcing is a documented, technically-necessary exception, not an unexplained inconsistency.
- Standard apps get one consistent values-composition story that matches every other resource's overlay treatment (per [ADR 0004](0004-kustomize-overlays.md)), at the cost of no longer being reconciliation-tool-agnostic for Helm values — a future GitOps-tool switch would need to re-port every app's values out of its `HelmRelease` CR, the same kind of translation cost already paid once for the ArgoCD→Flux migration.
- The historical `HelmChartInflationGenerator`/`valuesInline` + 2-level `generators:` pattern (inspired by `wmiller112`'s demo) is visible in git history as an intermediate step, not the live pattern for most apps today.
