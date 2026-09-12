# Kustomize overlay approach

Every unit under `k8s/infra/` and `k8s/apps/` (an "app") and every entry under `k8s/bootstrap/cluster/flux/sets/`
(a Flux "set" — see [`k8s/bootstrap/README.md`](../../k8s/bootstrap/README.md)) is built with
[kustomize](https://kustomize.io/), composed the same way across all 8 environments
(`dbg`, `dev`, `head`, `poc`, `prod`, `qa`, `rebuild`, `src`). The goal is to describe each app **once**,
environment-agnostically, and only spell out the handful of values that actually differ per environment
(a Service's load-balancer IP, a replica count, the reconciliation interval, the domain, ...).

## The `base` / `envs/<env>` / `flux` triad

Every app follows the same three-folder shape, e.g. [`k8s/apps/dns/adguard`](../../k8s/apps/dns/adguard):

```
📁 adguard
├── 📁 base                 # environment-agnostic manifests
│   ├── kustomization.yaml
│   ├── ns.yaml
│   ├── deployment.yaml
│   ├── svc.yaml
│   └── ...
├── 📁 envs
│   ├── 📁 dev              # dev-only overrides
│   │   ├── kustomization.yaml
│   │   └── svc.yaml        # patch, not a full copy
│   ├── 📁 qa
│   │   ├── kustomization.yaml
│   │   ├── svc.yaml
│   │   ├── merge-deployment.yaml
│   │   └── config/AdGuardHome.yaml
│   └── ...                 # one folder per environment that deploys this app
└── 📁 flux
    ├── kustomization.yaml
    └── ks.yaml              # the Flux Kustomization CR for this app
```

- **`base/`** holds a plain `Kustomization` with every resource the app needs, written as if there were only
  one environment. It never hardcodes a real domain (`example.com` is used as a placeholder — see
  [Transformers and `replacements`](#transformers-and-replacements) below) and never bakes in
  environment-specific values.
- **`envs/<env>/`** is a thin overlay: it pulls in `resources: [../../base]`, includes the shared
  [`components/envs/<env>`](#the-shared-components-layer) component (see below), and lists only the
  `patches:` needed for that environment. Only add a file here for a value that genuinely differs per
  environment — never duplicate a whole manifest just to change one field.
- **`flux/`** contains the Flux `Kustomization` custom resource (`ks.yaml`) that tells Flux to reconcile this
  app, plus a `kustomization.yaml` wrapping it as a resource. `ks.yaml`'s `spec.path` is always written
  pointing at `.../base` — the [`replace-path`](#flux-path-rewriting-replace-path) transformer is what
  rewrites it to `.../envs/<env>` per environment; the app folder itself never contains a
  `flux/ks.yaml` per environment.

Example `flux/ks.yaml` ([`k8s/apps/dns/adguard/flux/ks.yaml`](../../k8s/apps/dns/adguard/flux/ks.yaml)):

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: adguard
spec:
  interval: 1h
  path: ./k8s/apps/dns/adguard/base
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  wait: true
```

## Overlay patches

`envs/<env>/kustomization.yaml` lists overrides under `patches:`. Kustomize auto-detects whether a patch
file is a strategic-merge patch (a partial resource keyed by `apiVersion`/`kind`/`metadata.name`) or a
JSON6902 patch; every patch in this repo is a strategic-merge patch, e.g. overriding just the load-balancer
IP annotation on a `Service` ([`k8s/apps/dns/adguard/envs/dev/kustomization.yaml`](../../k8s/apps/dns/adguard/envs/dev/kustomization.yaml)):

```yaml
# envs/dev/kustomization.yaml
components:
  - ../../../../../components/envs/dev
resources:
  - ../../base
patches:
  - path: svc.yaml
```

```yaml
# envs/dev/svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: adguard
  annotations:
    io.cilium/lb-ipam-ips: 10.8.3.53
```

An overlay can list multiple patches, and can generate its own environment-local resources alongside them.
For example, `qa` gives AdGuard Home its own local config instead of the one baked into `base/` — it adds a
second `configMapGenerator` entry and a `merge-deployment.yaml` patch that repoints the Deployment's volume
at that new ConfigMap ([`k8s/apps/dns/adguard/envs/qa/kustomization.yaml`](../../k8s/apps/dns/adguard/envs/qa/kustomization.yaml)):

```yaml
# envs/qa/kustomization.yaml
namespace: adguard   # needed for the configMapGenerator below to land in the right namespace
components:
  - ../../../../../components/envs/qa
resources:
  - ../../base
patches:
  - path: svc.yaml
  - path: merge-deployment.yaml
configMapGenerator:
  - name: adguard-config-local
    files:
      - config/AdGuardHome.yaml
```

```yaml
# envs/qa/merge-deployment.yaml — strategic-merge patch pointing the volume at the new ConfigMap
apiVersion: apps/v1
kind: Deployment
metadata:
  name: adguard
spec:
  template:
    spec:
      volumes:
        - name: config
          configMap:
            name: adguard-config-local
```

## The shared `components` layer

[`k8s/components/`](../../k8s/components/README.md) holds the DRY layer every app/infra overlay includes via
`components:` — a [kustomize Component](https://kubectl.docs.kubernetes.io/guides/config_management/components/)
is a reusable, composable set of resources/patches/transformers, unlike a plain `Kustomization` which cannot
be included by another `Kustomization`.

```
📁 components
├── 📁 envs
│   ├── 📁 base       # domain replacement, labels, path rewriting, flux defaults — shared by every env
│   ├── 📁 dev        # dev's cluster-param ConfigMap + prefix-domain
│   ├── 📁 prod       # prod's cluster-param ConfigMap, prefix-domain intentionally NOT included
│   └── 📁 ...        # one per environment
└── 📁 transformers
    ├── 📁 add-labels          # add common labels, e.g. reconcile.fluxcd.io/watch: "Enabled"
    ├── 📁 prefix-domain       # dev-app.example.com — env prefix in front of the domain
    ├── 📁 replace-domain      # example.com -> your.sub.domain.com
    ├── 📁 replace-path        # rewrite Flux Kustomization spec.path: .../base -> .../envs/<env>
    └── 📁 set-flux-defaults   # set Flux Kustomization/HelmRelease reconciliation intervals
```

Every environment's component (e.g. [`components/envs/dev/kustomization.yaml`](../../k8s/components/envs/dev/kustomization.yaml))
follows the same pattern: it defines a `cluster-param` ConfigMap with that environment's values, and includes
`../base` (which in turn wires up `add-labels`, `replace-domain`, `replace-path`, `set-flux-defaults` against a
`cluster-base-param` ConfigMap):

```yaml
# components/envs/dev/cluster-param.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-param
  annotations:
    config.kubernetes.io/local-config: "true"
data:
  CLUSTER_ENVIRONMENT: dev
  DOMAIN_BASE: dev.iseja
  DOMAIN_TLD: net
  FLUX_RECONCILIATION_INTERVAL: 10m
```

```yaml
# components/envs/dev/kustomization.yaml
resources:
  - cluster-param.yaml
components:
  - ../base                          # configures domain replacement, labels, path rewriting, flux defaults
  - ../../transformers/prefix-domain
```

`config.kubernetes.io/local-config: "true"` marks these ConfigMaps as kustomize-only inputs — they're consumed
by the `replacements` below but are not meant to be applied to the cluster themselves.

An environment opts out of a shared transformer simply by not including it — `prod` includes `../base` (for
domain replacement, labels, etc.) but comments out `prefix-domain`, since prod's domain should not carry an
environment prefix ([`components/envs/prod/kustomization.yaml`](../../k8s/components/envs/prod/kustomization.yaml)):

```yaml
components:
  - ../base # configures domain replacements already
  # do not prefix domain
  # - ../../transformers/prefix-domain
```

## Transformers and `replacements`

Each transformer is itself a small `Component` under `components/transformers/<name>/kustomization.yaml`,
implemented with either a built-in
[transformer](https://kubectl.docs.kubernetes.io/references/kustomize/builtins/) (`add-labels`, via a
`LabelTransformer`) or kustomize's
[`replacements`](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/replacements/)
field (all the others). A `replacements` entry copies a value from one resource field (`source`) into one or
more fields on other resources (`targets`), optionally splitting/rejoining it with `options.delimiter` and
`options.index` — that's how a single `cluster-param` ConfigMap value fans out into edits across many
resources of a given `kind`.

- **`replace-domain` / `prefix-domain`** — swap the placeholder `example.com` for the real domain, across
  every `Ingress`/`HTTPRoute`/`TLSRoute`/`Gateway`/`Certificate` resource (apps in this repo route traffic
  via the Gateway API, so in practice it's `HTTPRoute`/`Gateway`/`Certificate` that get rewritten; the
  `Ingress` replacement exists for completeness but currently has nothing to match). `replace-domain` splits
  a hostname on `.` and replaces the two rightmost segments with `DOMAIN_BASE`/`DOMAIN_TLD` from the
  `cluster-param` ConfigMap — e.g. [`replace-domain/repl/httproute-replace-domain.yaml`](../../k8s/components/transformers/replace-domain/repl/httproute-replace-domain.yaml)
  turns `adguard.example.com` (`spec.hostnames.*` in [`k8s/apps/dns/adguard/base/http-route.yaml`](../../k8s/apps/dns/adguard/base/http-route.yaml))
  into `adguard.dev.iseja.net` in the `dev` environment. `prefix-domain` then prepends
  `CLUSTER_ENVIRONMENT` as an extra dash-delimited segment in front of the resulting hostname (so `dev` +
  `adguard.dev.iseja.net` becomes `dev-adguard.dev.iseja.net`) — every non-prod environment includes it,
  `prod` does not (see above), so only prod's hostnames stay unprefixed.
- **`add-labels`** — a built-in `LabelTransformer` that stamps `reconcile.fluxcd.io/watch: "Enabled"` onto
  every `ConfigMap`, so Flux's Helm Controller notices a ConfigMap change and immediately upgrades the
  `HelmRelease` that mounts it, rather than waiting for the next reconciliation interval.
- **`set-flux-defaults`** — copies `FLUX_RECONCILIATION_INTERVAL` from `cluster-param` into `spec.interval`
  of every Flux `Kustomization` and `HelmRelease`, so each environment can reconcile at a different cadence
  (e.g. `10m` in `dev`, `1h` in `prod`) without every app having to hardcode it.
- **`replace-path`** (see below) — rewrites `spec.path` on every Flux `Kustomization`.

### Flux path rewriting (`replace-path`)

Every app's `flux/ks.yaml` is written with `spec.path: ./k8s/apps/.../base`. `replace-path` is what turns
that into `./k8s/apps/.../envs/<env>` for a given environment, in two `replacements` steps
([`components/transformers/replace-path/repl/flux-kustomize-path.yaml`](../../k8s/components/transformers/replace-path/repl/flux-kustomize-path.yaml)):

1. Replace path segment index 5 (the literal `base`) with `envs/example`, using the fixed placeholder
   `cluster-base-param` ConfigMap's `ENVKEY` — turning `.../base` into `.../envs/example`.
2. Replace path segment index 6 (the placeholder `example`) with `CLUSTER_ENVIRONMENT` from `cluster-param` —
   turning `.../envs/example` into `.../envs/dev` (or whichever environment is active).

This only matters where Flux `Kustomization` resources are actually present as `kind: Kustomization` objects
in the tree being built — i.e. where all the apps'/infra's `flux/ks.yaml` files are aggregated together, not
inside each individual app's own `envs/<env>/kustomization.yaml` (which only overlays that app's own
resources like Services or ConfigMaps). That aggregation happens under
`k8s/bootstrap/cluster/flux/sets/` (grouped into `infra`/`apps`, each split into `minimal`/`optional`) and
per-environment under `k8s/bootstrap/cluster/flux/envs/<env>/`, which is where `components/envs/<env>` is
applied a second time — this time against the aggregated Flux `Kustomization` resources, rewriting every
app's and every infra unit's `spec.path` in one pass:

```yaml
# k8s/bootstrap/cluster/flux/envs/dev/kustomization.yaml
components:
  - ../../../../../components/envs/dev
resources:
  - ../../sets/minimal
```

## Sorting and other conventions

Field/list ordering inside these files (`kustomization.yaml`, Flux `Kustomization`/`HelmRelease`, and any
other manifest) follows [`.agents/instructions/sorting.md`](../../.agents/instructions/sorting.md).
