---
status: current
---

# Immich Database Backup & Restore

**Choose a task:** check or trigger a backup under [Daily tasks](#daily-tasks); set up the alert under [Alerting](#alerting); recover the database under [Restore](#restore); rehearse it under [Restore drill](#restore-drill); update Immich, PostgreSQL or VectorChord under [Upgrading](#upgrading).

**On this page:** [Overview](#overview) · [How it works](#how-it-works) · [Why a superuser](#why-a-superuser) · [Daily tasks](#daily-tasks) · [Encryption key](#encryption-key-age) · [Alerting](#alerting) · [Restore](#restore) · [Restore drill](#restore-drill) · [Upgrading](#upgrading) · [Why a dump and no WAL archiving](#why-a-dump-and-no-wal-archiving) · [Known caveats](#known-caveats)

## At a glance

| | |
| --- | --- |
| When to use | The Immich database is lost, broken or holds wrong content, or a dump from another environment has to be loaded. To check or trigger a backup see [Daily tasks](#daily-tasks). Before every Immich, PostgreSQL or VectorChord version change take a dump first: [Upgrading](#upgrading) |
| Prerequisites | `just`, `kubectl`, `flux`, `gum` and `jq` locally, the kube context `admin@<env>-homelab`, a dump in the `<env>-immich-db` bucket ([list them](#restore)) and, for an encrypted dump (`*.dump.age`), the age private key ([where it lives](#encryption-key-age)) |
| Steps | [Restore](#restore): `just backup::immich::restore -e <env> --identity <key file>`, four phases (select and verify, stop the writers, swap, start again). The same command restores into a fresh, empty cluster |
| Verify | [After the script](#restore): sign in to Immich and check albums, people (faces) and users; the script prints the row counts of the restored database |
| Rollback | [Roll back](#roll-back): possible until the old database `immich_before_<timestamp>` is dropped |
| Last exercised | The dump upload and the restore script on a representative database in `dev` on 2026-11-15 (see [Restore drill](#restore-drill)); the full drill in `rebuild` is [not yet run](#restore-drill) |

## Overview

Immich keeps albums, people (faces), shares, users and the metadata of every asset in a single-instance [CloudNativePG](https://cloudnative-pg.io/) cluster, `immich-db` in the `immich` namespace ([`k8s/apps/media/immich-db/`](../../k8s/apps/media/immich-db/)). The media files live on `fiona` and do not depend on it, but **the database is the part that cannot be regenerated from the files** ([ADR 0018](../decisions/0018-media-source-of-truth.md)): Immich does not scan its upload library for state, so without the database an upload library is a pile of files. Two independent copies exist:

| Copy | What | Where | Taken |
| --- | --- | --- | --- |
| Logical dump of this unit | `pg_dump --format=custom`, encrypted with [age](https://github.com/FiloSottile/age), the last 14 kept | bucket `<env>-immich-db` on `fiona` (RustFS) | daily 02:00 Europe/Berlin |
| Immich's own dump | `pg_dumpall` output as `.sql.gz`, restorable from the Immich web UI | `UPLOAD_LOCATION/backups` on the upload dataset on `fiona`, which `fiona`'s own backups cover ([#2144](https://github.com/isejalabs/homelab/issues/2144)) | Immich job, default daily 02:00, keep 14 (default of the Immich release, set by the [Immich unit](https://github.com/isejalabs/homelab/issues/2146)) |

What a restore from a dump up to 24 h old loses: assets uploaded, albums changed and faces named since the dump. The files of those uploads are on `fiona`, but Immich does not know them; the recovery is to import them again. This is the accepted recovery point for `dev`, `qa` and `rebuild`. **`prod` has not decided it yet**: it is decided with the promotion ([#2149](https://github.com/isejalabs/homelab/issues/2149)), because phone uploads arrive all day and 24 h may be too long for a family archive.

## How it works

- **Schedule**: the `immich-db-dump` `CronJob` runs every day at 02:00 (`Europe/Berlin`), see [`cronjob-dump.yaml`](../../k8s/apps/media/immich-db/base/cronjob-dump.yaml). It is the Keycloak dump job, see [`keycloak-backup-restore.md`](../identity/keycloak-backup-restore.md#how-it-works) for the reasoning behind its three steps, with the Immich names.
- **Steps in one pod**: an init container runs `pg_dump --format=custom` against `immich-db-rw` with the application credentials from the `immich-db-app` secret and checks the file with `pg_restore --list`; `fetch-age` puts the pinned `age` binary next to it; the main container encrypts to the public key(s) in `AGE_RECIPIENTS`, uploads `immich-<UTC timestamp>.dump.age`, deletes everything but the newest 14 dumps and pings the [heartbeat](#alerting) where one is configured. A plaintext dump is never uploaded.
- **Credentials and bucket**: the access key comes from the `immich-db-backup` secret, delivered by External Secrets from the 1Password item `immich-db#<env>`. The bucket `<env>-immich-db`, its scoped RustFS user and that item are created by the Terragrunt unit `rustfs-immich-db` (see [`terragrunt/README.md`](../../terragrunt/README.md)). **Apply that unit before the Flux unit is registered in an environment.** A freshly created bucket answered every upload with `ServiceUnavailable: Bucket quota check temporarily unavailable` for about 8 minutes (seen in `dev`); the first dump job after the apply may fail for that reason, and the next one succeeds. The bucket has a 10 GiB quota (the module default).
- **Client version**: `pg_dump` must be at least as new as the server. The server image is pinned in `spec.imageName` of [`cluster.yaml`](../../k8s/apps/media/immich-db/base/cluster.yaml) and a kustomize replacement in [`kustomization.yaml`](../../k8s/apps/media/immich-db/base/kustomization.yaml) copies it into the dump job, so the two cannot drift apart. The restore script builds its Job from the dump CronJob, so it restores with the same image.
- **Where it runs**: `dev`, `qa` and `rebuild`, registered in [`flux/envs/<env>/kustomization.yaml`](../../k8s/bootstrap/cluster/flux/envs/). `prod` follows with [#2149](https://github.com/isejalabs/homelab/issues/2149).

## Why a superuser

Decision for [#2145](https://github.com/isejalabs/homelab/issues/2145): **Immich's database role `immich` is a PostgreSQL superuser** (`managed.roles` in [`cluster.yaml`](../../k8s/apps/media/immich-db/base/cluster.yaml)).

| | Superuser (chosen) | Restricted owner |
| --- | --- | --- |
| Immich's own dumps | work | do not: the [docs](https://github.com/immich-app/immich/blob/v3.4.1/docs/docs/administration/postgres-standalone.md) state that automated backups need superuser, because they use `pg_dumpall` |
| Extension updates | Immich runs them itself on start | `ALTER EXTENSION vchord UPDATE` and two `REINDEX` by hand after every VectorChord change, and "often requires manual intervention when updating Immich" (same page) |
| Blast radius | the role can do anything inside this cluster | limited to the `immich` database |

The blast radius is small here: the cluster holds only the `immich` database, it is not reachable from outside, and the credentials live in one Secret that only Immich and the dump job read. Giving up Immich's own dump (the second copy, restorable from the UI) for it would cost more than it buys. The extensions are created at bootstrap anyway (`postInitApplicationSQL`), so a restricted setup stays possible later without a migration; revisit if the cluster ever hosts another database.

## Daily tasks

Check the last runs (an alert is described under [Alerting](#alerting); this is the manual check):

```sh
kubectl get cronjob,job -n immich --context admin@<env>-homelab
```

Trigger a backup now (for example before a risky change, see also [Upgrading](#upgrading)):

```sh
kubectl create job --from=cronjob/immich-db-dump manual-$(date +%Y%m%d-%H%M) -n immich --context admin@<env>-homelab
kubectl logs job/manual-<...> -c upload -n immich --context admin@<env>-homelab
```

List the dumps in the bucket with `just backup::immich::list -e <env>`, or by hand with the credentials of the `immich-db#<env>` 1Password item (`aws --endpoint-url https://fiona.home.iseja.net:9000 s3 ls s3://<env>-immich-db`, with `AWS_DEFAULT_REGION=default`).

## Encryption key (age)

The dumps hold password hashes, API keys and sharing links, so each one is encrypted before it leaves the cluster, with the same scheme as Keycloak's ([`keycloak-backup-restore.md`](../identity/keycloak-backup-restore.md#encryption-key-age)): the job knows only the **public** key, the private key is needed on the day of a restore.

**The dump job reuses the public key of the Keycloak dumps** (`AGE_RECIPIENTS` in [`cronjob-dump.yaml`](../../k8s/apps/media/immich-db/base/cronjob-dump.yaml)), so there is one recovery key to keep, and its private key is the existing 1Password item `keycloak-db age key` in a vault the cluster cannot read. A dedicated key for Immich is a one-line change of `AGE_RECIPIENTS` (add the new public key next to this one); rotation works as described for Keycloak, and dumps stay readable only with the key they were encrypted to. A restore passes the key with `--identity`, for example straight from 1Password without writing it to disk:

```sh
just backup::immich::restore -e <env> --identity <(op read 'op://IT Infrastructure/keycloak-db age key/password')
```

The script puts the key into a temporary Secret that only the restore Job mounts and deletes it right after that Job ended (also if the run is aborted).

## Alerting

A dump that fails, or never runs, must not go unnoticed. As for Keycloak there are two layers ([details](../identity/keycloak-backup-restore.md#alerting)):

| Layer | Catches | Covers |
| --- | --- | --- |
| **Heartbeat** ([healthchecks.io](https://healthchecks.io/)) | A dump that did not complete and upload by the time the check expects it, including a job that never started | Every environment that has a check |
| **Checkmk** `kube_cronjob_status` | A CronJob whose latest job failed | Only the environments feeding a `*_k8s` site (`qa_k8s` notifies, `prod_k8s` does not yet, [#1901](https://github.com/isejalabs/homelab/issues/1901)) |

**Heartbeat setup per environment** (not done yet, an owner task, see [#2145](https://github.com/isejalabs/homelab/issues/2145)): create a healthchecks.io check with `period` 1 day and `grace time` 2 hours; create the 1Password item `immich-db-heartbeat#<env>` in the `K8S` vault with the field `HEARTBEAT_URL`; copy [`externalsecret-heartbeat.yaml`](../../k8s/apps/identity/keycloak/envs/qa/externalsecret-heartbeat.yaml) from the Keycloak unit into `envs/<env>/` with the names changed and list it under `resources:`. The dump job already reads the Secret `immich-db-heartbeat` as optional, so nothing else changes. Test the alert as described for Keycloak. `qa` and `prod` get a check; `dev` and `rebuild` none, as for Keycloak.

## Restore

> [!WARNING]
> Immich is down from phase 2 (stop the writers) until phase 4 has finished.

Restoring takes the newest (or a chosen) dump and swaps it in for the live `immich` database with [`scripts/ops/immich/db-restore.sh`](../../scripts/ops/immich/db-restore.sh). Nothing is deleted: the dump is restored into a scratch database `immich_restore` next to the live one, checked, and the two are swapped by renaming once everything that writes has been stopped. The previous database stays in the cluster until you drop it. **The same procedure is the recovery into a fresh, empty cluster**: recreate the cluster by letting Flux reconcile the unit (it creates an empty `immich` database with the extensions), then run the script.

You need `just`, `kubectl`, `flux`, `gum` and `jq` locally and the kube context `admin@<env>-homelab`. A restore always names its environment:

```sh
just backup::immich::list -e <env>                                              # dumps in the bucket: key, last modified, size
just backup::immich::restore -e <env> --identity <key file>                     # newest dump
just backup::immich::restore -e <env> --identity <key file> --dump <key>        # a chosen dump
```

What the script does, in this order (the first change to the live database is the rename in phase 3):

| Phase | What happens | Immich |
| --- | --- | --- |
| 1. Select and verify | Lists the bucket, picks the dump (the newest unless `--dump`), creates `immich_restore` and loads the dump into it with a Job built from the `immich-db-dump` CronJob (same images, credentials and bucket). A dump that does not restore stops here. Prints tables, users, assets, albums, faces and the VectorChord version of the live and the restored database and asks for confirmation. | running |
| 2. Stop the writers | Suspends the Flux Kustomization `immich` (the Immich unit, if it exists in the environment) and the `immich-db-dump` CronJob (and waits for a running dump), scales every Deployment and StatefulSet in the namespace except Valkey to 0 and waits until no client is connected to the database. | down |
| 3. Swap | In one transaction: `immich` becomes `immich_before_<timestamp>`, `immich_restore` becomes `immich`. | down |
| 4. Start again | Resumes Flux, scales the workloads back to their previous replicas and restores the CronJob's suspend flag. | starting |

If anything fails between phase 2 and the swap, the script resumes Flux, the workloads and the CronJob and the live database is untouched; after the swap it only starts the workloads again.

**After the script**, in Immich: sign in, open an album, open *People* (faces) and *Administration > Users*, and check that the newest asset you expect from before the dump is there. Immich may run database migrations on start when the dump is from an older version; that is normal. The VectorChord indexes (`face_index`, `clip_index`) come back with the dump, no reindex is needed while the extension version is unchanged.

### Roll back

Until the old database is dropped, the swap can be undone: stop the Immich workloads as phase 2 does (`flux suspend kustomization immich`, scale to 0), then in `psql` as the superuser rename `immich` to a spare name and `immich_before_<timestamp>` back to `immich`, and start the workloads. **Drop the old database** when you are satisfied; the script prints the command.

### A dump from another environment

Copy the dump into the target's `<env>-immich-db` bucket first (each environment's user only reaches its own bucket), then restore it as above. What comes with the dump: every user and album of the source, and file paths that must exist in the target's media (a non-prod environment sees only copies of the library on test datasets, [#413](https://github.com/isejalabs/homelab/issues/413)), so a dump taken in `qa` is not useful in `dev` beyond testing the procedure.

## Restore drill

The drill proves the procedure end to end and records how long it takes. Owner-coordinated, in `rebuild` ([#2145](https://github.com/isejalabs/homelab/issues/2145)):

1. Needs a merged state: Terragrunt `rustfs-immich-db` applied in `rebuild`, the unit registered in `rebuild` (merged to `main`), and Immich running in `qa` with a few albums, named people and users so there is something to verify ([#2146](https://github.com/isejalabs/homelab/issues/2146)).
2. Copy the newest `qa` dump into the `rebuild-immich-db` bucket.
3. Start Immich in `rebuild` against the same read-only media copy ([#2144](https://github.com/isejalabs/homelab/issues/2144)) with an empty database, or only the database to check the numbers.
4. `just backup::immich::restore -e rebuild --identity <key file> --dump <key>`; record the `restore_seconds` and total the script prints.
5. In Immich: albums, people and users match `qa`; a smart search and a face search return results.

| Date | What | Result |
| --- | --- | --- |
| 2026-11-15 | Command rehearsal in `dev` on a stand-in database: tables `user`, `asset`, `album`, `asset_face` and `smart_search` with 5000 assets, 2000 face and 2000 smart-search embeddings and the two VectorChord indexes. `pg_dump --format=custom` and `pg_restore --no-owner --exit-on-error` into a scratch database as the `immich` role, run from the dump job's own image | Dump 271 KB, checks passed, restore 13 s, indexes `face_index` and `clip_index`, `vchord` 1.1.1 and `vector` 0.8.6 came back, row counts equal. Run without S3 (RustFS on `fiona` was down at that time) and without the script's swap |
| 2026-11-15 | End to end in `dev` on the same stand-in database: the `immich-db-dump` CronJob run by hand (encrypted dump into the bucket `dev-immich-db`), then `just backup::immich::restore -e dev -y --identity <key file>` | Dump 271 KB uploaded, decrypted and restored into `immich_restore` in 13 s; users 2, assets 5000, albums 3, faces 2000 and `vchord` 1.1.1 equal to the live database; swap and restart 29 s in total, CronJob suspend flag and Flux back to normal. Without real Immich and not in `rebuild` |
| Not yet | Full drill in `rebuild` with the script, an encrypted dump from the bucket and real Immich | open, waits for the points above |

## Upgrading

**Before every Immich, PostgreSQL or VectorChord version change take a dump** ([Daily tasks](#daily-tasks)), wait for the job to complete and check the object in the bucket. The newest 14 are kept, so a pre-upgrade dump is pruned after two weeks of daily dumps; copy it aside if the change is to be rolled back later. Also check that Immich's own dump of the same day exists in *Administration > Maintenance*.

### Immich

An Immich release has a supported range for the database. Check it against the release you deploy: PostgreSQL `>= 14, < 20`, VectorChord `>= 0.3, < 2.0`, pgvector `>= 0.7, < 0.9` for v3.4.1 (from `docs/docs/administration/postgres-standalone.md` in the Immich source at that tag); the server refuses to start with an incompatible VectorChord. Test the release in `qa` before `prod` ([#2149](https://github.com/isejalabs/homelab/issues/2149)).

### PostgreSQL (minor and patch)

The image tag and digest in `spec.imageName` of [`cluster.yaml`](../../k8s/apps/media/immich-db/base/cluster.yaml). A Renovate PR changes it; the dump job follows through the replacement. Take a dump, [`track-branch`](../../.agents/skills/track-branch/SKILL.md) the PR in `dev` or `qa`, wait for `kubectl get cluster -n immich` to report a healthy cluster (a minor update restarts the instance in place), then merge.

### VectorChord

A new VectorChord version arrives with the image tag (`<PostgreSQL>-<VectorChord>`). After the instance runs the new image, update the extension and rebuild the two indexes. With a superuser Immich does this itself on its next start; by hand, in `psql` as the superuser:

```sql
ALTER EXTENSION vchord UPDATE;
REINDEX INDEX face_index;
REINDEX INDEX clip_index;
```

### PostgreSQL major

A major version is `pg_upgrade` territory and not a tag bump: Renovate does not propose it. The way that stays inside this unit's mechanisms is a dump and restore: take a dump, change `spec.imageName` to the new major on a **fresh** cluster (delete the cluster and its PVC in a non-`prod` environment first, or use a new environment), let Flux create it, then run the [restore](#restore). Immich supports PostgreSQL 14 to 19 for v3.4.1, so there is no urgency. CloudNativePG's in-place major upgrade is an alternative to be evaluated when it is needed; none is documented here yet.

## Why a dump and no WAL archiving

The reasoning is the one of Keycloak ([`keycloak-backup-restore.md`](../identity/keycloak-backup-restore.md#why-a-dump-and-no-wal-archiving)): no archive means a failing backup target can never make WAL pile up on the volume, and a database of this size (1 to 3 GB for a large library, [Immich requirements](https://github.com/immich-app/immich/blob/v3.4.1/docs/docs/install/requirements.md)) dumps in a minute or two. The price is the 24 h recovery point; point-in-time recovery would need WAL archiving to RustFS and CloudNativePG's backup stack, which is a separate decision for `prod` if 24 h turns out too long. The WAL settings are sized for that: `max_wal_size` 1 GB on a 10 Gi volume.

## Known caveats

- **Sizing is provisional.** The volume (10 Gi, 3 Gi in `dev`), the memory (Immich documents at least 2 GB when limits are set; `dev` runs with a 1 Gi limit because its workers are small) and the dump job's scratch space (4 Gi) come from Immich's documentation, not from a measurement. The load test ([#2147](https://github.com/isejalabs/homelab/issues/2147)) sizes them for the full library; the bucket quota (10 GiB) has to grow with the dump size too.
- **The job's credential can delete every dump.** As for Keycloak, retention runs with the job's own credential; see the [caveat there](../identity/keycloak-backup-restore.md#known-caveats). A second, independent copy is Immich's own dump on `fiona`.
- **The dump job needs `github.com` at 02:00** to fetch `age`, as for Keycloak ([why](../identity/keycloak-backup-restore.md#why-age-is-downloaded)). Bump `age` by hand in both jobs.
- **`fiona` is a single point.** Both copies of the database, and the media, are on `fiona`; its own backups ([#2144](https://github.com/isejalabs/homelab/issues/2144)) are what stands behind them.
- **Nothing alerts yet on a failed dump in `dev` and `rebuild`** (by design, as for Keycloak), and in `qa` only once the [heartbeat](#alerting) is set up.
- **No network policy** around the database yet ([#1995](https://github.com/isejalabs/homelab/issues/1995)); the `immich-db-app` Secret holds a superuser.
