## Purpose

Points every Flux `Kustomization` at the overlay of the current environment. Each unit's `flux/ks.yaml` is written once with `spec.path: ./k8s/<apps|infra>/<group>/<unit>/base`; this transformer turns that into `.../envs/<env>`, so a unit never needs a `flux/ks.yaml` per environment.

## How it works

Two `replacements` in [`repl/flux-kustomize-path.yaml`](repl/flux-kustomize-path.yaml), both splitting `spec.path` on `/`:

1. Segment 5, the literal `base`, becomes `envs/example`. The source is `ENVKEY` (`envs/example`) of the placeholder `cluster-base-param` ConfigMap in [`components/envs/base`](../../envs/base/cluster-base-param.yaml), which is the same in every environment.
2. Segment 6, the placeholder `example`, becomes `CLUSTER_ENVIRONMENT` of the environment's `cluster-param`.

So `./k8s/apps/dns/adguard/base` becomes `./k8s/apps/dns/adguard/envs/example` and then `./k8s/apps/dns/adguard/envs/dev`.

The segment indexes assume the fixed depth `./k8s/<apps|infra>/<group>/<unit>/base`. A `spec.path` with another depth is rewritten at the wrong segment, so keep it in that shape (see [`k8s/README.md`](../../../README.md#shape-of-an-appinfra-unit)).

## Where it's included

Through [`components/envs/base`](../../envs/base/kustomization.yaml), so all 8 environments get it. It only matters where Flux `Kustomization` objects are in the build: not in a unit's own `envs/<env>` overlay, but in the aggregated build under `k8s/bootstrap/cluster/flux/envs/<env>`, which applies `components/envs/<env>` to the units registered in the Flux sets and so rewrites every unit's path in one pass.

A longer walkthrough, including the `kustomization.yaml` of that aggregated build, is in [`docs/architecture/kustomize.md`](../../../../docs/architecture/kustomize.md#flux-path-rewriting-replace-path).
