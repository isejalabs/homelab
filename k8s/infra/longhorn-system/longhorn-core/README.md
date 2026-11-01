# Longhorn core

[Longhorn](https://longhorn.io/) is the distributed block storage of the cluster: it keeps replicas of each volume on the worker nodes and serves ordinary dynamic `PersistentVolumeClaim`s. This unit is the Longhorn engine itself; its storage classes and recurring jobs are in [`longhorn`](../longhorn/README.md).

## At a glance

| | |
| --- | --- |
| Namespace | `longhorn-system` |
| Runs in | all 8 environments (Flux set `optional`; every environment includes the full infra set) |
| Installed via | HelmRelease, chart `longhorn` from the `charts.longhorn.io` Helm repository, plus an `HTTPRoute` for the UI and an `ExternalSecret` for the backup target credentials |
| Flux Kustomization | `longhorn-core`, depends on `infra-ns` |

## Purpose

Replicated volumes on the nodes' local disks (`/var/mnt/longhorn`), with snapshots and an S3 backup target, so apps do not depend on a Proxmox volume that Terragrunt has to declare. It is replacing [proxmox-csi](../../csi-proxmox/proxmox-csi/README.md) for app data. The comparison and the classes: [`storage.md`](../../../../docs/architecture/storage.md), [ADR 0014](../../../../docs/decisions/0014-longhorn-vs-proxmox-csi.md). The default replica count is 2; the classes in [`longhorn`](../longhorn/README.md) choose per app.

## Where it is used

- **Used by**: every app with a PVC on a `longhorn-*` class (through `apps/storage/pvc`, see [`app-storage.md`](../../../../docs/operations/app-storage.md)), the Keycloak database (`longhorn-ha`), and the kopiur backups, which snapshot and copy these volumes.
- **Depends on**: the worker nodes' disks, [`snapshot-controller`](../../kube-system/snapshot-controller/) for `VolumeSnapshot`s, and an S3 backup target (credentials from the 1Password item `longhorn-minio-credentials#<env>` via External Secrets; only `dev`, `prod`, `qa` and `rebuild` set a backup target, in their `envs/<env>/backup-target.yaml`).

## Access

The Longhorn UI is published through the `internal` Gateway under the subdomain `longhorn`.

| env | URL |
| --- | --- |
| `dbg` | `https://dbg-longhorn.dbg.iseja.net` |
| `dev` | `https://dev-longhorn.dev.iseja.net` |
| `head` | `https://head-longhorn.head.iseja.net` |
| `poc` | `https://poc-longhorn.poc.iseja.net` |
| `prod` | `https://longhorn.prod.iseja.net` |
| `qa` | `https://qa-longhorn.qa.iseja.net` |
| `rebuild` | `https://rebuild-longhorn.rebuild.iseja.net` |
| `src` | `https://src-longhorn.src.iseja.net` |

The route is on the `internal` Gateway, so it is reachable from the LAN only. Hostname scheme: [`reference/environments.md`](../../../../docs/reference/environments.md#domain-and-naming).

## Updates

- **Chart**: `spec.chart.spec.version` in [`base/helmrelease.yaml`](base/helmrelease.yaml). `prod` pins its own copy in [`envs/prod/helm-version.yaml`](envs/prod/helm-version.yaml), so a version PR for `prod` is separate and, being labeled `env:prod`, always waits for a manual merge: [Tracking a version separately per environment](../../../../docs/operations/update-handling.md#tracking-a-version-separately-per-environment).
- Read Longhorn's upgrade notes before a minor bump (engine and volume versions); the pre-upgrade checker job is disabled here.
- `prod`, `qa` and `rebuild` run two replicas of the CSI sidecars instead of one (`envs/<env>/csi-replicacount.yaml`).

## Operations

| Task | Doc |
| --- | --- |
| Local snapshots, restore an app to a snapshot | [`longhorn-snapshots.md`](../../../../docs/backup/longhorn-snapshots.md) |
| Backup and restore of app data | [`kopiur-backup-restore.md`](../../../../docs/backup/kopiur-backup-restore.md) |
| PVC or volume stuck, orphaned volumes of `Retain` classes | [`troubleshooting-storage.md`](../../../../docs/troubleshooting/troubleshooting-storage.md), [`storage.md`](../../../../docs/architecture/storage.md#reclaimpolicy-retain-and-the-two-step-cleanup-gotcha) |

## Cheat sheet

Replace `<env>` with the environment.

```sh
flux get ks longhorn-core longhorn --context admin@<env>-homelab
kubectl get pods -n longhorn-system --context admin@<env>-homelab

# volumes, replicas and nodes (Longhorn custom resources)
kubectl get volumes.longhorn.io,replicas.longhorn.io -n longhorn-system --context admin@<env>-homelab
kubectl get nodes.longhorn.io -n longhorn-system --context admin@<env>-homelab

# claims and the classes they use
kubectl get pvc -A --context admin@<env>-homelab
kubectl get storageclass --context admin@<env>-homelab
```

## Upstream

- Homepage and documentation: <https://longhorn.io/>, <https://longhorn.io/docs/>
- Source and releases: <https://github.com/longhorn/longhorn>
