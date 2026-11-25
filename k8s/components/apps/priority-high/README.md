## Purpose

Opt-in of one app for the scheduling priority `homelab-high`, the class the infra units run with (see [`infra/common/priority-classes`](../../../infra/common/priority-classes/README.md)). An app is listed here on purpose: a forgotten app stays at the default priority, the safe direction. The infra units do not use this component; the [`set-priority-class`](../../transformers/set-priority-class/README.md) transformer covers them through their Flux set.

## How it works

The patches in [`kustomization.yaml`](kustomization.yaml) put `priorityClassName: homelab-high` on every `Deployment`, `StatefulSet` and `DaemonSet` of the unit, and a `HelmRelease` gets the same through a `spec.postRenderers` entry (the chart renders the pods, not the unit).

## Where it's included

Add `../../../../components/apps/priority-high` to `components:` in the unit's `base/kustomization.yaml`. Today: `checkmk-agent`, `powerdns` and `unbound`.

Not through this component:

- **keycloak**: the Keycloak and CloudNativePG pods are created by operators from custom resources, so the class is set in the resources themselves (`spec.unsupported.podTemplate.spec.priorityClassName` in `keycloak.yaml`, `spec.priorityClassName` in `cluster.yaml`).
- **metrics-server**: its pod already runs with `system-cluster-critical`, which is above `homelab-high`.

## Limits

A `HelmRelease` that already has its own `spec.postRenderers` is replaced. `CronJob`s and `Job`s are not touched.
