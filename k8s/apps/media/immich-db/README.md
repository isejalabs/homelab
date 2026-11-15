# Immich database

The PostgreSQL database and the Valkey cache that [Immich](https://immich.app/) runs on, as one unit that the Immich unit ([#2146](https://github.com/isejalabs/homelab/issues/2146)) depends on. The database holds albums, faces, shares, users and the metadata of every asset: the part of Immich that cannot be regenerated from the media files.

## At a glance

| | |
| --- | --- |
| Namespace | `immich` (created by this unit, `base/ns.yaml`; the Immich unit uses the same namespace and does not create it) |
| Runs in | `dev`, `qa`, `rebuild` (Flux set `qa-soaking`) |
| Installed via | Custom resource `Cluster` (CloudNativePG), a `Deployment` and a `Service` for Valkey, a `CronJob` for the database dump, an `ExternalSecret` for the backup credentials; the server is created by the [CloudNativePG operator](../../../infra/cnpg-system/cloudnative-pg/README.md) |
| Flux Kustomization | `immich-db`, depends on `cloudnative-pg`, `longhorn` |

## Purpose

Immich becomes the online archive for the family photos and videos ([#413](https://github.com/isejalabs/homelab/issues/413), [ADR 0018](../../../../docs/decisions/0018-media-source-of-truth.md)). Its database is run like the Keycloak one: a single-instance CloudNativePG cluster on Longhorn, no WAL archiving, and a daily encrypted `pg_dump` to RustFS instead. The image is [`cloudnative-vectorchord`](https://github.com/tensorchord/cloudnative-vectorchord), the CloudNativePG system image plus the VectorChord extension that the Immich chart recommends. Tracking issue: [#2145](https://github.com/isejalabs/homelab/issues/2145).

## Where it is used

- **Used by**: the Immich unit ([#2146](https://github.com/isejalabs/homelab/issues/2146)). The names it can rely on, which are the contract between the two units:

  | What | Value |
  | --- | --- |
  | Namespace | `immich` |
  | Database service (read-write) | `immich-db-rw` (port 5432) |
  | Database, user | `immich`, `immich` (a superuser, see [why](../../../../docs/backup/immich-database.md#why-a-superuser)) |
  | Secret with the credentials | `immich-db-app`, keys `host`, `port`, `dbname`, `username`, `password`, `uri` (a ready `postgresql://` URL for `DB_URL`) |
  | Valkey service | `immich-valkey` (port 6379), no password, no persistence; `REDIS_HOSTNAME=immich-valkey` |
  | Flux Kustomization to `dependsOn` | `immich-db` |

- **Depends on**: [Longhorn](../../../infra/longhorn-system/longhorn-core/README.md) for the volume (`longhorn-ha`), the CloudNativePG operator, and RustFS on `fiona` plus the 1Password item `immich-db#<env>` for the dump (created by the Terragrunt unit `rustfs-immich-db`).

## Access

Not exposed. The database is reachable in-cluster only, through `immich-db-rw.immich` (primary) and `immich-db-ro.immich`; Valkey through `immich-valkey.immich`. There is no network policy yet, as for Keycloak (see [`keycloak-exposure.md`](../../../../docs/identity/keycloak-exposure.md)).

## Updates

- **PostgreSQL and VectorChord**: pinned with tag and digest in `spec.imageName` of [`base/cluster.yaml`](base/cluster.yaml); a kustomize replacement copies it into the dump job. The tag is `<PostgreSQL>-<VectorChord>`, for example `18.6-1.1.1`. Renovate proposes minor and patch updates of PostgreSQL 18 and VectorChord 1.x as manual PRs ([`pin-versions.json5`](../../../../.github/renovate/pin-versions.json5)); a PostgreSQL major or a VectorChord 2.x is outside what Immich supports and is not proposed. Procedure: [Upgrading](../../../../docs/backup/immich-database.md#upgrading).
- **Valkey**: image tag and digest in [`base/valkey.yaml`](base/valkey.yaml), taken from the Immich release's own compose file; the normal Renovate flow ([`update-handling.md`](../../../../docs/operations/update-handling.md)).
- **Per environment**: `dev`, `qa` and `rebuild` follow `base/`. `prod` is registered with the `prod` promotion of Immich ([#2149](https://github.com/isejalabs/homelab/issues/2149)) and gets its own pins then.

## Operations

| Task | Doc |
| --- | --- |
| Back up, restore, drill the restore, upgrade PostgreSQL and VectorChord | [`immich-database.md`](../../../../docs/backup/immich-database.md) |
| Flux unit stuck or failing | [`troubleshooting-flux.md`](../../../../docs/troubleshooting/troubleshooting-flux.md) |
| PVC or Longhorn volume problems | [`troubleshooting-storage.md`](../../../../docs/troubleshooting/troubleshooting-storage.md) |

## Cheat sheet

Replace `<env>` with `dev`, `qa` or `rebuild`. A cold start takes a few minutes: the database image is about 280 MB and is pulled on every node the pod lands on for the first time.

```sh
# state of the unit and of the workload
flux get ks immich-db --context admin@<env>-homelab
kubectl get cluster,pods,cronjob,externalsecret -n immich --context admin@<env>-homelab

# a psql session as the superuser (peer authentication in the pod)
kubectl exec -it -n immich immich-db-1 -c postgres --context admin@<env>-homelab -- psql -U postgres -d immich

# versions of PostgreSQL and of the extensions Immich checks
kubectl exec -n immich immich-db-1 -c postgres --context admin@<env>-homelab -- psql -U postgres -d immich -Atc "select version(); select extname, extversion from pg_extension order by 1"

# dumps: list, take one now, restore (see immich-database.md before restoring)
just backup::immich::list -e <env>
kubectl create job --from=cronjob/immich-db-dump manual-$(date +%Y%m%d-%H%M) -n immich --context admin@<env>-homelab
just backup::immich::restore -e <env> --identity <age private key file>

# Valkey answers?
kubectl exec -n immich deploy/immich-valkey --context admin@<env>-homelab -- valkey-cli ping
```

## Upstream

- Immich: <https://immich.app/>, source <https://github.com/immich-app/immich>; the database requirements are in its documentation under "Pre-existing Postgres" (`docs/docs/administration/postgres-standalone.md` in the source)
- Database image: <https://github.com/tensorchord/cloudnative-vectorchord>; extension: <https://github.com/tensorchord/VectorChord>
- CloudNativePG: <https://cloudnative-pg.io/>
- Valkey: <https://valkey.io/>
