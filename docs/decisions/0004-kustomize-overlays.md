# Kustomize overlays for the environment-variation axis

## Status

current

## Context

Every app/infra unit under `k8s/infra/`/`k8s/apps/` needs to be described once and deployed, with small per-environment differences (a load-balancer IP, a replica count, a reconciliation interval, the domain), across all [8 environments](0005-environments.md). Some of those units are themselves Helm charts (wrapped in a Flux `HelmRelease`, often via the [`bjw-s-labs` app-template](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/other/app-template) — e.g. PowerDNS); most are plain manifests. Kustomize's `base`/`envs/<env>`/`flux` triad (see [`kustomize.md`](../architecture/kustomize.md)) is the one mechanism used for the environment-variation axis across *both* kinds uniformly — a `HelmRelease` custom resource gets the same overlay/patch treatment as a plain `Deployment`, rather than leaning on Helm's own per-environment `values.yaml` files for the chart-based half of the repo and something else for the rest.

Helmfile is used elsewhere in this repo, but only for the one-time bootstrap stage (`k8s/bootstrap/helmfile/`, installing the handful of apps that must exist before Flux does) — it isn't the mechanism for ongoing, Flux-reconciled environment variation.

A separate, deliberate choice from the start: an app's `envs/<env>/` overlay lives as a sibling of its own `base/`, so everything that makes up one app stays in one place (`k8s/apps/<category>/<app>/{base,envs,flux}`) — rather than splitting the repo into one tree of apps and a separate `clusters/<cluster>/<app>/<overlay>` tree holding the per-cluster/per-environment overlay definitions, the structure most known Flux/home-ops examples and guides actually use. That divergence made adopting Flux (see [ADR 0009](0009-flux-vs-argocd.md)) noticeably more work than it otherwise would have been — the reference examples and guidance available at the time generally assumed the `clusters/A`/`clusters/B` split, not an app-colocated one, so the translation wasn't a drop-in. Note this folder choice is about *where an app's per-environment overlay lives*, not about *whether* environments are separated by folder rather than by git branch at all — that broader, tool-agnostic principle (shared with Terragrunt's own directory structure) is [ADR 0014](0014-folder-based-environments-not-branches.md).

## Options considered

- **Per-app Helm charts with per-environment `values-<env>.yaml` files (rejected)** — would need a chart to exist for every app, including ones that are just plain manifests today, and gives no uniform mechanism for patching the Flux `Kustomization`/`HelmRelease` resources themselves.
- **Helmfile per environment (rejected for ongoing use)** — already used for the bootstrap stage, but not adopted for everything Flux manages afterward.
- **Separate, fully-duplicated manifest trees per environment (rejected)** — the `kustomize.md` intro's explicit goal ("describe each app once, environment-agnostically") is precisely what this avoids.
- **Kustomize `base`/`envs/<env>`/`flux` overlays (chosen)** — one environment-agnostic `base/`, a thin `envs/<env>/` patch overlay per environment, and a shared [`components/envs/<env>`](../architecture/kustomize.md#the-shared-components-layer) layer for cross-cutting per-environment values (domain, reconciliation interval, ...) reused by every app rather than repeated in each one's own overlay.
- **A separate `clusters/<cluster>/<app>/<overlay>` tree, apps defined elsewhere (rejected)** — the structure most Flux/home-ops reference repos actually use. Rejected in favor of keeping everything that makes up one app (manifests and every environment's overlay of them) in one place, at the cost of extra friction when later adopting tooling/guidance that assumes the `clusters/A`/`clusters/B` split.
- **JSON6902 patches for overlay overrides (rejected as the default)** — every patch in this repo is a strategic-merge patch instead: a partial resource keyed by `apiVersion`/`kind`/`metadata.name` that only states what's actually overridden, easier to maintain as a small file that's almost — but not quite — a full resource definition, versus a JSON6902 patch's path-based operations. The tradeoff: an editor/language-server sometimes flags a strategic-merge patch file as "incomplete" (missing fields a full resource of that kind would normally require), since it has no way to know the file is intentionally partial.

## Decision

Kustomize overlays are the environment-variation mechanism for everything Flux reconciles, regardless of whether the underlying workload is a raw manifest or a Helm chart wrapped in a `HelmRelease`. Helm/Helmfile stays scoped to chart packaging (`bjw-s-labs` app-template and similar, for apps that are charts) and the one-time bootstrap stage, respectively — neither competes with kustomize for the environment-variation role. Helm is otherwise a deliberately independent choice from kustomize, not a sub-decision of this one — see [ADR 0006](0006-helm-usage.md) for how Helm values themselves are composed, and why that evolved away from being reconciliation-tool-agnostic.

## Consequences

- One consistent mental model and tool (`kustomize build`, `kubeconform`) validates every app/infra unit in CI ([`kustomize-build.yml`](../../.github/workflows/kustomize-build.yml)), regardless of whether it's a plain manifest or a `HelmRelease`.
- A cross-cutting per-environment value (e.g. the domain) is defined once in `components/envs/<env>` and consumed via `replacements`, rather than duplicated into every app's own values.
- Kustomize's `patches:`/`components:` model has its own learning curve and failure modes (e.g. strategic-merge vs. JSON6902 patch selection) distinct from Helm's templating model — anyone touching an app's overlay needs to understand both, since a chart-based app still goes through a kustomize overlay on top of its `HelmRelease`.
- The app-colocated folder structure (vs. a separate `clusters/` tree) made the ArgoCD→Flux migration (see [ADR 0009](0009-flux-vs-argocd.md)) a real translation effort rather than a drop-in adoption of existing guides/examples — a cost paid once, not recurring.
- A strategic-merge patch file can trip up an editor's own linting/schema validation (it looks like an incomplete resource definition) — a known, accepted cosmetic annoyance, not a functional problem.
