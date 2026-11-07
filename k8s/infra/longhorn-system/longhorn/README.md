# Longhorn classes and jobs

The configuration around [Longhorn core](../longhorn-core/README.md): the `StorageClass`es that choose a trade-off per app, the `VolumeSnapshotClass`, and the recurring jobs for snapshots and filesystem trim.

## At a glance

| | |
| --- | --- |
| Namespace | `longhorn-system` |
| Runs in | all 8 environments (Flux set `optional`); every environment includes the full infra set |
| Installed via | Raw Longhorn and Kubernetes resources in `base/`: `StorageClass`es, `VolumeSnapshotClass` `vsc-standard`, two `RecurringJob`s |
| Flux Kustomization | `longhorn`, depends on `longhorn-core` |

## Purpose

One driver, several profiles, so an app picks a class by what it needs (`STORAGE_CLASS` in its Flux Kustomization, see [`app-storage.md`](../../../../docs/operations/app-storage.md)). Filesystem, replica count and reclaim policy of every class are stated once, in [`storage.md`](../../../../docs/architecture/storage.md#storageclasses--one-driver-several-tradeoff-profiles), and not repeated here; the manifests are `base/sc-*.yaml`. Besides the data classes there are disposable ones for the kopiur mover (`longhorn-scratch-*`, `longhorn-cache`).

The recurring jobs take a snapshot every hour and trim filesystems weekly (Saturday 04:07), see [`base/job-snapshot.yaml`](base/job-snapshot.yaml) and [`base/job-fs-trim-default.yaml`](base/job-fs-trim-default.yaml).

## Where it is used

- **Used by**: every PVC that names a `longhorn-*` class (the `apps/storage/pvc` component defaults to `longhorn-standard`), and kopiur, which snapshots through `vsc-standard`.
- **Depends on**: [`longhorn-core`](../longhorn-core/README.md) for the driver and [`snapshot-controller`](../../kube-system/snapshot-controller/) for the snapshot CRDs.

## Access

Not exposed. The UI is that of [`longhorn-core`](../longhorn-core/README.md#access).

## Updates

No version of its own; the manifests follow the Longhorn release in `longhorn-core`. Renaming or changing a class does not affect existing PVCs (a `StorageClass` is immutable; add a new class instead).

## Operations

| Task | Doc |
| --- | --- |
| Pick a class, filesystem pairing, variables | [`app-storage.md`](../../../../docs/operations/app-storage.md) |
| Local snapshots and restore | [`longhorn-snapshots.md`](../../../../docs/backup/longhorn-snapshots.md) |
| Convert a PVC to another class | [`kopiur-backup-restore.md`](../../../../docs/backup/kopiur-backup-restore.md) (`just backup::kopiur::convert-storage-class`) |

## Cheat sheet

```sh
flux get ks longhorn --context admin@<env>-homelab
kubectl get storageclass,volumesnapshotclass --context admin@<env>-homelab
kubectl get recurringjobs.longhorn.io -n longhorn-system --context admin@<env>-homelab
```

## Upstream

- Documentation: <https://longhorn.io/docs/>, recurring jobs <https://longhorn.io/docs/latest/snapshots-and-backups/scheduling-backups-and-snapshots/>
