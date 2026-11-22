# infra-priority-classes (PriorityClass `homelab-high`)

Not a workload: the one unit that creates the cluster-wide scheduling priority the infra units and a short list of apps run with.

## At a glance

| | |
| --- | --- |
| Namespace | none (a `PriorityClass` is cluster-scoped) |
| Runs in | all 8 environments (Flux set `minimal`) |
| Installed via | Plain kustomize, one manifest in [`base/`](base/homelab-high.yaml) |
| Flux Kustomization | `infra-priority-classes`, no `dependsOn` |

## Purpose

Every workload has priority 0 unless it says otherwise (Immich runs at -100, the system and Longhorn pods at a very high value). Under memory or disk pressure the scheduler and the kubelet pick the lowest priority first. `homelab-high` (value 100000, preempting) puts the infra units and the apps monitoring, DNS and identity depend on above every ordinary app and below `longhorn-critical` and the system classes.

The class only exists here. Who gets it is decided elsewhere: the infra units by default through the [`set-priority-class`](../../../components/transformers/set-priority-class/README.md) component, which the infra sets include, and the apps by an explicit opt-in in their own unit.

## Where it is used

- **Used by**: every unit the `set-priority-class` component reaches, see its README.
- **Depends on**: nothing. Units that use the class carry no `dependsOn` on this one: a pod that names a class that does not exist yet is rejected, and the retry interval of the Flux `Kustomization` (1m) covers a cold bring-up.

## Access

Not exposed.

## Updates

No version. Changing the value only re-sorts the scheduler's choice, it never restarts a pod; a pod keeps the value it was admitted with, so a rolled value reaches a running pod with its next restart.

## Operations

Do not lower the value below another class in use (Immich's `immich` is -100, the default is 0) and do not raise it to or above `longhorn-critical` (1000000000): storage must keep winning over everything here.

## Cheat sheet

```sh
kubectl get priorityclass --context admin@<env>-homelab
kubectl get pods -A --context admin@<env>-homelab -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,PRIO:.spec.priorityClassName
```

## Upstream

None; this is a local construct. The shape of a unit is described in [`k8s/README.md`](../../../README.md#shape-of-an-appinfra-unit).
