# Flux over ArgoCD

## Status

current

## Context

ArgoCD came with [@vehagn](https://github.com/vehagn/homelab)'s reference repo (see [ADR 0001](0001-proxmox-and-talos.md)) — inherited the same way Talos/Cilium were, not separately evaluated at first. It was kept deliberately: its GUI made reconciliation status easy to explore, and its ApplicationSet generator drove an "app of apps" pattern that mapped cleanly onto this repo's own per-environment kustomize overlay folders. Throughout, the goal was staying reconciliation-tool-agnostic rather than leaning on ArgoCD-specific features — in particular, never adopting ArgoCD's native Helm-repository integration, sticking instead with kustomize's own `helmChartInflationGenerator`. That choice has real, documented drawbacks: Kustomize's own docs are explicit that Helm chart inflation is deliberately limited ("we cannot support the entire helm feature set"; no private-registry auth or other larger features) ([kustomize.sigs.k8s.io](https://kustomize.sigs.k8s.io/references/kustomize/kustomization/helmcharts)) — Helm support in kustomize was never going to be first-class.

Several things pulled toward Flux. First, the pattern observed across other homelab repos in the "home-ops" community: dominant Flux usage, native cross-resource dependency declarations (`dependsOn` on a `Kustomization`/`HelmRelease`) with no good ArgoCD equivalent, and variable substitution for templating (Flux's `postBuild.substitute`). This project's own domain-style values (e.g. `DOMAIN_BASE`) use kustomize's `replacements` instead (see [ADR 0004](0004-kustomize-overlays.md)) — but Flux's `postBuild.substitute` is the actual, designed-for mechanism for a different case: letting an app easily parameterize things like its PVC size/filesystem when consuming a kopiur-backed volume (`STORAGE_CLASS`, `STORAGE_CAPACITY`, ... — see [`app-storage.md`](../app-storage.md)), rather than needing a kustomize patch for every app that wants a non-default value. Second, wanting to adopt application definitions directly from other home-ops repos (mirceanton's, onedr0p's) meant translating ArgoCD-shaped config from Flux-shaped source repos by hand, every time, with no AI tooling support yet (the migration itself happened in winter 2026, before AI-assisted development started in 9/2026) — targeting the same tool as the source repos removed that translation tax. Separately, Flux was also wanted as the prerequisite for adopting the kopiur/VolSync-style pattern (seen in mirceanton's and onedr0p's repos) of restoring an app's data automatically from its last backup on cluster bootstrap — this is about what that pattern is built on in the reference repos, not a claim that kopiur itself couldn't have worked with ArgoCD.

There was also a research-driven hesitation worth recording honestly: around the time of evaluation, Flux's own future looked uncertain for a stretch — Weaveworks, Flux's main corporate sponsor, shut down in early 2024, and it took time for CNCF and other companies (GitLab among them) to confirm continued maintenance ([sdtimes.com](https://sdtimes.com/softwaredev/state-of-gitops-now-in-flux-as-weaveworks-shuts-down/), [GitLab](https://about.gitlab.com/blog/the-continued-support-of-fluxcd-at-gitlab/)). That risk didn't end up materializing — Flux is CNCF-graduated and actively maintained today — but it was a real factor weighed at the time, not something to paper over.

## Options considered

- **Stay on ArgoCD (rejected)** — the GUI advantage and app-of-apps pattern were real, but didn't outweigh the translation tax of adopting Flux-shaped app definitions from the home-ops community, or the lack of a clean cross-resource dependency primitive.
- **Flux CD (chosen)** — native `dependsOn`, direct compatibility with the home-ops ecosystem's Flux-shaped app definitions, and a prerequisite for the kopiur/VolSync-style automatic-restore-on-bootstrap pattern.

## Decision

Flux CD reconciles every `k8s/infra`/`k8s/apps` unit from Git; ArgoCD has been fully decommissioned (migration: 3/2026-8/2026, done by hand — "the last big implementation done without AI guidance", root [`README.md`](../../README.md#a-bit-of-history)).

## Consequences

- Every app/infra unit's Flux `Kustomization` points directly at a kustomize path (`base` or, via the `replace-path` transformer, `envs/<env>`), with real `dependsOn` relationships between units — e.g. [`longhorn`/`longhorn-core`](../../k8s/infra/longhorn-system/longhorn/flux/ks.yaml) — rather than an ArgoCD `Application`/`ApplicationSet` layer.
- `postBuild.substitute` is available as a per-app, per-environment-overridable knob without a kustomize patch — used by [`apps/storage/pvc`](../app-storage.md)'s `STORAGE_*` variables, though as of this writing no app has exercised it yet (designed-for, not yet established in practice).
- In hindsight (learned after adopting AI-assisted development in 9/2026), application-level dependency management (e.g. "this app needs that database") was never really the gap to solve — the real, recurring need is *structural* dependencies (a CRD that must exist before a dependent resource can apply), which `dependsOn` handles regardless of which GitOps tool provides it.
- The GUI advantage that originally justified keeping ArgoCD wasn't actually given up: Flux's own ecosystem (flux-operator's UI) provides the same kind of cluster-manifest-status exploration. ArgoCD's imperative/write-side UI capabilities were used read-only in practice anyway, so losing them wasn't a real limitation.
- Porting an app from an `onedr0p`/mirceanton-style home-ops reference repo is now a more direct translation, formalized as this repo's own [`port-app`](../../.agents/skills/port-app/SKILL.md) skill.
