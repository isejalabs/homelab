# kopiur

[kopiur](https://github.com/home-operations/kopiur) is the backup and restore operator, built on [Kopia](https://kopia.io/). It snapshots an app's volume on a schedule, copies it to an S3 repository, and restores a fresh, empty volume of an app from its last snapshot.

## At a glance

| | |
| --- | --- |
| Namespace | `kopiur-system` |
| Runs in | all 8 environments (Flux set `optional`; every environment includes the full infra set), but active backup schedules only in `dev`, `prod`, `qa` and `rebuild` |
| Installed via | HelmRelease, chart from the OCI repository `ghcr.io/home-operations/charts/kopiur` ([`base/ocirepository.yaml`](base/ocirepository.yaml)); the per-app wiring is the `apps/storage/pvc` component |
| Flux Kustomization | `kopiur`, depends on `infra-ns` |

## Purpose

Every app that stores data and uses `apps/storage/pvc` gets a daily backup and automatic restore-on-create: delete the volume or rebuild the cluster and the app comes back with its data. In `dbg`, `head`, `poc` and `src` all schedules are forced to suspended by the `suspend-kopiur-schedule` transformer. The design, the credits to upstream and the caveats: [`kopiur-backup-restore.md`](../../../../docs/backup/kopiur-backup-restore.md); the storage side: [`app-storage.md`](../../../../docs/operations/app-storage.md).

## Where it is used

- **Used by**: every app with `apps/storage/pvc` or `pvc-no-backup`: `actualbudget`, `powerdns`, `unifi-controller`, `unifi-mongodb`, `zigbee2mqtt` and others (the exact set is whatever includes the component).
- **Depends on**: [`kopiur-repository`](../kopiur-repository/README.md) (the S3 repository `fiona`), [`snapshot-controller`](../../kube-system/snapshot-controller/) and the `VolumeSnapshotClass` from [`longhorn`](../../longhorn-system/longhorn/README.md) for point-in-time copies.

## Access

Not exposed. Metrics, a Prometheus rule and a Grafana dashboard are enabled in the chart values; nothing scrapes them yet because there is no Prometheus stack in the cluster.

## Updates

- **Chart**: tag and digest in [`base/ocirepository.yaml`](base/ocirepository.yaml). The operator is a young project, so read its release notes before a minor bump. No special Renovate rule: the default flow of [`update-handling.md`](../../../../docs/operations/update-handling.md) applies.

## Operations

| Task | Doc |
| --- | --- |
| List, trigger, restore, bypass-restore, prune | [`kopiur-backup-restore.md`](../../../../docs/backup/kopiur-backup-restore.md#daily-tasks) |
| Volume or backup problems | [`troubleshooting-storage.md`](../../../../docs/troubleshooting/troubleshooting-storage.md) |
| Rebuild a whole cluster | [`disaster-recovery.md`](../../../../docs/backup/disaster-recovery.md) |

## Cheat sheet

The `just` recipes wrap the commands in the backup doc; each takes `-e <env>` and `-n <namespace>`.

```sh
just backup::kopiur::list <app> -e <env> -n <namespace>       # snapshots of an app
just backup::kopiur::create <app> -e <env> -n <namespace>     # backup now
just backup::kopiur::create --all -e <env> -n <namespace>     # every app in a namespace

flux get ks kopiur kopiur-repository --context admin@<env>-homelab
kubectl get pods -n kopiur-system --context admin@<env>-homelab
kubectl get snapshotpolicies,snapshotschedules,snapshots,restores -A --context admin@<env>-homelab
```

## Upstream

- Source and releases: <https://github.com/home-operations/kopiur>
- Kopia: <https://kopia.io/docs/>
