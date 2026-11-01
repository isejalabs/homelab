# kopiur repository

The `ClusterRepository` `fiona` for [kopiur](../kopiur/README.md): the S3-compatible NAS where all backups of an environment are stored, one bucket per environment.

## At a glance

| | |
| --- | --- |
| Namespace | `kopiur-system` (the `ClusterRepository` itself is cluster-scoped) |
| Runs in | all 8 environments (Flux set `optional`; every environment includes the full infra set) |
| Installed via | Raw kopiur resource ([`base/clusterrepository.yaml`](base/clusterrepository.yaml)); the credentials Secret `kopiur-repository-secret` is created by an `ExternalSecret` from the `apps/kopiur` component |
| Flux Kustomization | `kopiur-repository`, depends on `kopiur`, `onepassword-connect` |

## Purpose

Tells kopiur where and how to store backups: the S3 endpoint `fiona.home.iseja.net:9000`, the bucket, the encryption password (Kopia encrypts client-side), and the maintenance schedule (quick every hour, full daily at 03:00, both with jitter). It also sets the mover cache budgets, sized to fit the smallest cache volume, and the Berlin time zone for schedules.

## Where it is used

- **Used by**: kopiur and, through it, every backed-up app in any namespace (`allowedNamespaces.all`).
- **Depends on**: the NAS `fiona` (outside this repo), and the 1Password item `kopiur-backup#<env>` with the access key and the Kopia password, delivered by External Secrets. The per-environment bucket (`<env>-kopiur-backup`) and item name are produced by the `kopiur-secret-env` transformer from the `base-` and `#base` values in `base/`: [`kopiur-secret-env`](../../../components/transformers/kopiur-secret-env/README.md).

## Access

Not exposed in the cluster. The bucket is on the NAS's S3 endpoint [https://fiona.home.iseja.net:9000](https://fiona.home.iseja.net:9000); use the RustFS or S3 tooling there to inspect it.

## Updates

No version. Changes are to the endpoint, schedules or cache settings in `base/clusterrepository.yaml`. The cache sizes were ported from upstream after it hit the same bug (see the credits in [`kopiur-backup-restore.md`](../../../../docs/backup/kopiur-backup-restore.md#credits--changes-from-upstream)).

## Operations

| Task | Doc |
| --- | --- |
| Backup, restore, prune | [`kopiur-backup-restore.md`](../../../../docs/backup/kopiur-backup-restore.md#daily-tasks) |
| Per-environment credentials and buckets | [`kopiur-backup-restore.md`](../../../../docs/backup/kopiur-backup-restore.md#automatic-per-env-credentials) |
| RustFS capacity | [`2026-10-rustfs-capacity.md`](../../../../docs/audits/2026-10-rustfs-capacity.md) (point-in-time audit, not current state) |

## Cheat sheet

```sh
flux get ks kopiur-repository --context admin@<env>-homelab
kubectl get clusterrepository fiona --context admin@<env>-homelab
kubectl describe clusterrepository fiona --context admin@<env>-homelab    # connection state and maintenance status
kubectl get externalsecret -n kopiur-system --context admin@<env>-homelab
```

## Upstream

- Kopiur documentation and releases: <https://github.com/home-operations/kopiur>
