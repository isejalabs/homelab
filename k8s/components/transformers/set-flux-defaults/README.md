## Purpose

Gives every Flux `Kustomization` and `HelmRelease` the reconciliation settings of the environment instead of a value hardcoded in each unit's `flux/ks.yaml` or `HelmRelease`:

- `spec.interval` of both kinds comes from `FLUX_RECONCILIATION_INTERVAL` in the environment's `cluster-param` ConfigMap (`10m` in `dbg`, `dev`, `poc`, `rebuild`, `src`; `1h` in `head`, `prod`, `qa`, see [`reference/environments.md`](../../../../docs/reference/environments.md#flux-reconciliation-interval)).
- `spec.retryInterval: 1m` on every `Kustomization`, so a unit that fails during a cold bring-up is retried after a minute and not after a whole `spec.interval` (`10m` or `1h`).

The retry interval is the repo's answer to ordering races that cannot be expressed as a `dependsOn`: for example an app's kopiur `SnapshotPolicy` is rejected until the `kopiur-repository` unit has created the `ClusterRepository` that kopiur's admission webhook reads. A `dependsOn` is still the tool for an ordering that must hold at all times, see [`docs/architecture/kustomize.md`](../../../../docs/architecture/kustomize.md#transformers-and-replacements).

## How it works

Two `replacements` files in [`repl/`](repl) copy `data.FLUX_RECONCILIATION_INTERVAL` from `cluster-param` into `spec.interval`, one for `kustomize.toolkit.fluxcd.io/v1` `Kustomization`s and one for `helm.toolkit.fluxcd.io/v2` `HelmRelease`s. The value is copied whole, so it needs no delimiter.

The retry interval is a JSON6902 patch in [`kustomization.yaml`](kustomization.yaml), selected by kind and group (`Kustomization`, `kustomize.toolkit.fluxcd.io`):

```yaml
- op: add
  path: /spec/retryInterval
  value: 1m
```

## Where it's included

Through [`components/envs/base`](../../envs/base/kustomization.yaml), so all 8 environments get it. Each kind is changed where it is part of the build: a unit's `HelmRelease` in the unit's own `envs/<env>` overlay, a Flux `Kustomization` in the aggregated build under `k8s/bootstrap/cluster/flux/envs/<env>` (see [`replace-path`](../replace-path/README.md#where-its-included)). Elsewhere a `select` matches nothing and does nothing.
