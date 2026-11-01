# infra-ns (namespace registration)

Not a workload but a registration point: the one Flux Kustomization that creates all namespaces of the infra units, so they exist before anything is deployed into them.

## At a glance

| | |
| --- | --- |
| Namespace | none of its own: it creates the namespaces listed in [`base/kustomization.yaml`](base/kustomization.yaml) |
| Runs in | all 8 environments (Flux set `minimal`) |
| Installed via | Plain kustomize aggregation of every group's `_ns/base` folder |
| Flux Kustomization | `infra-ns`, no `dependsOn` |

## Purpose

Namespaces for infra are created once and centrally, not by each unit, because several units share one namespace (for example `kube-system`, `gateway-api`, `keycloak`) and a namespace should have a single owner. Each `_ns/base/ns.yaml` carries `kustomize.toolkit.fluxcd.io/prune: disabled`, so removing a namespace from the list never deletes it with its content. Apps are different: they bring their own `ns.yaml` in `base/` and do not use this unit.

## Where it is used

- **Used by**: every infra unit that sets `dependsOn: infra-ns` (for example `gateway`, `snapshot-controller`, `cloudnative-pg`, `keycloak-operator`).
- **Depends on**: nothing.

## Access

Not exposed.

## Updates

No version. Changes are additions to the list when a new infra group needs a namespace.

## Operations

To give a new infra group a namespace, add `<group>/_ns/base` (a `kustomization.yaml` plus an `ns.yaml`) and one line `- ../../../<group>/_ns/base` to [`base/kustomization.yaml`](base/kustomization.yaml), in alphabetical order. The `namespace:` key must stay commented out there, because it would override the namespaces of the aggregated resources. The steps for a ported component: the `port-app` skill.

## Cheat sheet

```sh
flux get ks infra-ns --context admin@<env>-homelab
kubectl get ns --context admin@<env>-homelab

# what is the list this environment applies?
kubectl kustomize k8s/infra/common/ns/envs/<env> | grep -A1 'kind: Namespace' | grep 'name:'
```

## Upstream

None; this is a local construct. The shape of a unit and of the `_ns` folder is described in [`k8s/README.md`](../../../README.md#shape-of-an-appinfra-unit).
