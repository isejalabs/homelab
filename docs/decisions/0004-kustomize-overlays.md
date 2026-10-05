# Kustomize overlays for the environment-variation axis

## Status

current

## Context

Every app/infra unit under `k8s/infra/`/`k8s/apps/` needs to be described once and deployed, with small per-environment differences (a load-balancer IP, a replica count, a reconciliation interval, the domain), across all [8 environments](0005-eight-environments.md). Some of those units are themselves Helm charts (wrapped in a Flux `HelmRelease`, often via the [`bjw-s-labs` app-template](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/other/app-template) — e.g. PowerDNS); most are plain manifests. Kustomize's `base`/`envs/<env>`/`flux` triad (see [`kustomize.md`](../architecture/kustomize.md)) is the one mechanism used for the environment-variation axis across *both* kinds uniformly — a `HelmRelease` custom resource gets the same overlay/patch treatment as a plain `Deployment`, rather than leaning on Helm's own per-environment `values.yaml` files for the chart-based half of the repo and something else for the rest.

Helmfile is used elsewhere in this repo, but only for the one-time bootstrap stage (`k8s/bootstrap/helmfile/`, installing the handful of apps that must exist before Flux does) — it isn't the mechanism for ongoing, Flux-reconciled environment variation.

## Options considered

- **Per-app Helm charts with per-environment `values-<env>.yaml` files (rejected)** — would need a chart to exist for every app, including ones that are just plain manifests today, and gives no uniform mechanism for patching the Flux `Kustomization`/`HelmRelease` resources themselves.
- **Helmfile per environment (rejected for ongoing use)** — already used for the bootstrap stage, but not adopted for everything Flux manages afterward.
- **Separate, fully-duplicated manifest trees per environment (rejected)** — the `kustomize.md` intro's explicit goal ("describe each app once, environment-agnostically") is precisely what this avoids.
- **Kustomize `base`/`envs/<env>`/`flux` overlays (chosen)** — one environment-agnostic `base/`, a thin `envs/<env>/` patch overlay per environment, and a shared [`components/envs/<env>`](../architecture/kustomize.md#the-shared-components-layer) layer for cross-cutting per-environment values (domain, reconciliation interval, ...) reused by every app rather than repeated in each one's own overlay.

## Decision

Kustomize overlays are the environment-variation mechanism for everything Flux reconciles, regardless of whether the underlying workload is a raw manifest or a Helm chart wrapped in a `HelmRelease`. Helm/Helmfile stays scoped to chart packaging (`bjw-s-labs` app-template and similar, for apps that are charts) and the one-time bootstrap stage, respectively — neither competes with kustomize for the environment-variation role. Helm is otherwise a deliberately independent choice from kustomize, not a sub-decision of this one — see [ADR 0006](0006-helm-usage.md) for how Helm values themselves are composed and kept tool-agnostic.

## Consequences

- One consistent mental model and tool (`kustomize build`, `kubeconform`) validates every app/infra unit in CI ([`kustomize-build.yml`](../../.github/workflows/kustomize-build.yml)), regardless of whether it's a plain manifest or a `HelmRelease`.
- A cross-cutting per-environment value (e.g. the domain) is defined once in `components/envs/<env>` and consumed via `replacements`, rather than duplicated into every app's own values.
- Kustomize's `patches:`/`components:` model has its own learning curve and failure modes (e.g. strategic-merge vs. JSON6902 patch selection) distinct from Helm's templating model — anyone touching an app's overlay needs to understand both, since a chart-based app still goes through a kustomize overlay on top of its `HelmRelease`.
