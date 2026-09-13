See [`docs/architecture/workloads.md`](../docs/architecture/workloads.md) for a full catalog of every app and
infra component actually deployed — what each one is, and how it's installed.

## Folder Structure

```
📁 k8s
├── 📁 apps                     # application workloads, grouped by domain
│   ├── 📁 diag                   # e.g. whoami
│   ├── 📁 dns                    # e.g. adguard, unbound
│   ├── 📁 finances                # e.g. actualbudget
│   ├── 📁 monitoring              # e.g. checkmk-agent, metrics-server
│   └── 📁 network                # e.g. unifi-controller
├── 📁 bootstrap                # second bootstrap phase: helmfile + Flux hand-off (see bootstrap/README.md)
│   ├── 📁 cluster/flux           # Flux `sets/` (infra|apps × minimal|optional), composed per env under flux/envs/<env>
│   ├── 📁 helmfile               # helmfile definitions: crds/, apps/, base/, templates/*.gotmpl
│   └── 📁 kustomize/personal     # personal credentials injected via `op inject` during bootstrap
├── 📁 components               # shared DRY kustomize layer (see components/README.md)
│   ├── 📁 envs                   # per-environment Components included by every app/infra overlay
│   └── 📁 transformers           # transformers those components apply (replace-path, replace-domain, prefix-domain, add-labels, set-flux-defaults)
├── 📁 infra                    # infrastructure workloads, grouped by namespace
│   ├── 📁 cert-manager
│   ├── 📁 common/ns              # aggregates every group's `_ns` base into one Flux Kustomization ("infra-ns")
│   ├── 📁 csi-proxmox
│   ├── 📁 external-secrets
│   ├── 📁 flux-system
│   ├── 📁 gateway-api
│   ├── 📁 kube-system
│   ├── 📁 longhorn-system
│   ├── 📁 o11y
│   └── 📁 sealed-secrets
└── 📁 test                     # throwaway manifests for manually exercising things (e.g. storage classes); not reconciled by Flux
```

### Shape of an app/infra unit

Every leaf under `apps/<domain>/<app>` and `infra/<namespace>/<component>` follows the same three-folder shape (with one exception, `_ns`, below):

```
📁 <app-or-component>
├── 📁 base          # environment-agnostic manifests + kustomization.yaml (placeholder domain example.com)
├── 📁 envs/<env>    # per-environment overlay: includes ../../../../../components/envs/<env> and patches only what differs
└── 📁 flux          # the Flux Kustomization (ks.yaml) reconciling this unit, plus its own kustomization.yaml
```

`flux/ks.yaml`'s `spec.path` is written pointing at `base/` but gets rewritten to `envs/<env>/` per environment by the `replace-path` transformer (see `components/README.md`).

A `_ns` folder (e.g. `infra/cert-manager/_ns`) is the exception: it only has a `base/` with the namespace manifest, no `envs/`/`flux/` of its own. Every group's `_ns/base` is pulled in as a resource by `infra/common/ns`, which is the one Flux Kustomization (`infra-ns`) that actually creates all infra namespaces.

## Kustomize overlay approach

See [`docs/architecture/kustomize.md`](../docs/architecture/kustomize.md) for how the `base`/`envs/<env>`/`flux`
overlay triad, overlay patches, the shared `components` layer, and its `replacements`-based transformers
(domain rewriting, common labels, Flux `spec.path`/`spec.interval` rewriting) fit together.
