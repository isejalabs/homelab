## Purpose

Gives the pods of every infra unit the scheduling priority `homelab-high` without a line in each unit, so a new infra unit is covered by default and a forgotten line cannot leave it at the default priority of 0. The class itself is created by [`infra/common/priority-classes`](../../../infra/common/priority-classes/README.md); the value and the reasoning are there.

## How it works

One JSON6902 patch in [`kustomization.yaml`](kustomization.yaml) selects every Flux `Kustomization` (`kustomize.toolkit.fluxcd.io`) of the set that does not carry the label `homelab.iseja.net/self-managed-priority` and adds a `spec.patches` list to it. Flux applies that list to what the unit builds:

- a `HelmRelease` gets `spec.postRenderers` with a kustomize patch for `Deployment`, `StatefulSet` and `DaemonSet`: the chart is not ours, so the patch goes on the rendered objects;
- a plain `Deployment`, `StatefulSet` or `DaemonSet` in the unit is patched directly.

`CronJob`s and `Job`s are not touched, and neither are pods that an operator creates from a custom resource (CloudNativePG database pods, the Keycloak pods): for those the priority belongs in the custom resource itself.

## Where it's included

In the three Flux sets, not in an environment: [`sets/infra/minimal`](../../../bootstrap/cluster/flux/sets/infra/minimal/kustomization.yaml), [`sets/infra/optional`](../../../bootstrap/cluster/flux/sets/infra/optional/kustomization.yaml) and [`sets/standing`](../../../bootstrap/cluster/flux/sets/standing/kustomization.yaml) (cloudnative-pg and keycloak-operator, plus the Keycloak app that lives in that set). Every environment that names one of these sets gets it.

## Rules for a unit

- **Opt out** with `metadata.labels: homelab.iseja.net/self-managed-priority: "true"` in the unit's `flux/ks.yaml` when its pods already have a system or Longhorn class; the patch would downgrade them. Today: `cilium`, `proxmox-csi`, `kubelet-serving-cert-approver`, `snapshot-controller`, `longhorn`, `longhorn-core` and `flux-instance`.
- **No `spec.patches` of its own** on a unit in these sets: the component replaces the list. Use a patch in the unit's `base/` or `envs/<env>/` instead, which is not a Flux-side patch.
- **A `HelmRelease` with its own `spec.postRenderers`** is replaced the same way; move that post-render logic into the chart values or the overlay first.

## Checking

```sh
kubectl kustomize k8s/bootstrap/cluster/flux/envs/<env> | yq 'select(.kind == "Kustomization" and .spec.patches) | .metadata.name'
kubectl get pods -A --context admin@<env>-homelab -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,PRIO:.spec.priorityClassName
```
