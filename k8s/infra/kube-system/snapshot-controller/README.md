# snapshot-controller

The CSI [snapshot-controller](https://github.com/kubernetes-csi/external-snapshotter) watches `VolumeSnapshot` objects and drives the CSI driver to create and delete the snapshots. The `VolumeSnapshot` CRDs come with its chart.

## At a glance

| | |
| --- | --- |
| Namespace | `kube-system` |
| Runs in | all 8 environments (Flux set `minimal`) |
| Installed via | HelmRelease, chart from the OCI repository `ghcr.io/home-operations/charts/snapshot-controller` ([`base/ocirepository.yaml`](base/ocirepository.yaml)); the CRDs are also pre-installed by the bootstrap `crds` helmfile, the release itself is Flux-only |
| Flux Kustomization | `snapshot-controller`, depends on `infra-ns` |

## Purpose

Kubernetes ships the snapshot API but not the controller. Longhorn's local snapshots and the kopiur backups of every app that uses `apps/storage/pvc` start from a `VolumeSnapshot`, so this must be healthy before any backup runs. One replica; leader election is relaxed (10 s renewals) to write less to etcd.

## Where it is used

- **Used by**: Longhorn (the `VolumeSnapshotClass` in [`longhorn`](../../longhorn-system/longhorn/)) and, through it, kopiur ([`kopiur`](../../kopiur-system/kopiur/)) for every backed-up app: [`kopiur-backup-restore.md`](../../../../docs/backup/kopiur-backup-restore.md).
- **Depends on**: the `VolumeSnapshot` CRDs (bootstrap) and a CSI driver that supports snapshots.

## Access

Not exposed. The chart enables a `ServiceMonitor` for its metrics; nothing scrapes it yet because there is no Prometheus stack in the cluster.

## Updates

- **Chart**: tag and digest in [`base/ocirepository.yaml`](base/ocirepository.yaml). No special Renovate rule: the default flow of [`update-handling.md`](../../../../docs/operations/update-handling.md) applies. The CRDs are extracted from the same chart for the bootstrap, see [`k8s/bootstrap/README.md`](../../../bootstrap/README.md).

## Operations

| Task | Doc |
| --- | --- |
| Backups fail or no snapshot is taken | [`kopiur-backup-restore.md`](../../../../docs/backup/kopiur-backup-restore.md), [`troubleshooting-storage.md`](../../../../docs/troubleshooting/troubleshooting-storage.md) |
| Longhorn local snapshots | [`longhorn-snapshots.md`](../../../../docs/backup/longhorn-snapshots.md) |

## Cheat sheet

```sh
flux get ks snapshot-controller --context admin@<env>-homelab
kubectl get pods -n kube-system -l app.kubernetes.io/name=snapshot-controller --context admin@<env>-homelab

# snapshots and their classes
kubectl get volumesnapshotclass --context admin@<env>-homelab
kubectl get volumesnapshot,volumesnapshotcontent -A --context admin@<env>-homelab
```

## Upstream

- Source and releases: <https://github.com/kubernetes-csi/external-snapshotter>
- Documentation: <https://kubernetes-csi.github.io/docs/snapshot-controller.html>
