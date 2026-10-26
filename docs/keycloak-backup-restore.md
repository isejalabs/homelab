---
status: current
---

# Keycloak Database Backup & Restore

**Choose a task:** check or trigger a backup under [Daily tasks](#daily-tasks); recover the database under [Restore](#restore).

**On this page:** [Overview](#overview) · [How it works](#how-it-works) · [Daily tasks](#daily-tasks) · [Restore](#restore) · [Why a dump and no WAL archiving](#why-a-dump-and-no-wal-archiving) · [Known caveats](#known-caveats)

## Overview

Keycloak (see [#1826](https://github.com/isejalabs/homelab/issues/1826)) keeps its state in a single-instance [CloudNativePG](https://cloudnative-pg.io/) cluster, `keycloak-db` in the `keycloak` namespace ([`k8s/apps/identity/keycloak/`](../k8s/apps/identity/keycloak/)). It is backed up with a **daily logical dump** (`pg_dump`), uploaded to a per-environment bucket on `fiona`, the S3-compatible NAS (`<env>-keycloak-db`).

What is in the database, and what a restore from the latest dump loses:

| Content | After a restore from a dump up to 24 h old |
| --- | --- |
| Realm configuration | Comes back with the dump; once realms are managed as code it also comes back from Git |
| Users imported from UCS | Come back with the dump; re-synced from UCS anyway |
| Sessions | Lost for anything created since the dump; users sign in again |
| MFA enrollments (WebAuthn keys, TOTP secrets) | Lost for anything enrolled since the dump; those users must **enroll again**, which for the `admin` realm needs [break-glass access](keycloak-break-glass.md) |

The accepted target is a recovery point of 24 h (the design plan, [`docs/plans/2026-10-identity-claude.md`](plans/2026-10-identity-claude.md)): a database loss is a break-glass situation anyway, so the last day of sessions and new enrollments may be lost.

## How it works

- **Schedule**: the `keycloak-db-dump` `CronJob` runs every day at 02:00 (`Europe/Berlin`), see [`cronjob-dump.yaml`](../k8s/apps/identity/keycloak/base/cronjob-dump.yaml).
- **Two steps in one pod**: an init container runs `pg_dump --format=custom` against the read-write service `keycloak-db-rw` with the application credentials from the `keycloak-db-app` secret (created by CloudNativePG), writing to an `emptyDir`. The main container uploads the file as `keycloak-<UTC timestamp>.dump` with the AWS CLI and then deletes everything but the newest 14 dumps. A failed dump leaves nothing to upload, so a broken dump never replaces a good one.
- **Credentials and bucket**: the access key comes from the `keycloak-db-backup` secret, delivered by External Secrets from the 1Password item `keycloak-db#<env>`. The bucket `<env>-keycloak-db`, its scoped RustFS user and that item are created by the Terragrunt unit `rustfs-keycloak-db` (see [`terragrunt/README.md`](../terragrunt/README.md)). **Apply that unit before the Flux units are registered in an environment.**
- **Client version**: `pg_dump` must be at least as new as the server. The CronJob uses the same `ghcr.io/cloudnative-pg/postgresql` image as the cluster. When the cluster moves to a new PostgreSQL major version, bump the CronJob image with it.
- **Where it runs**: only in the environments that register the units (currently `dev` and `qa`; see [`sets/soaking`](../k8s/bootstrap/cluster/flux/sets/soaking/kustomization.yaml)).

## Daily tasks

Check the last runs (a failed job is not alerted yet, look here):

```sh
kubectl get cronjob,job -n keycloak --context admin@<env>-homelab
```

Trigger a backup now (for example before a risky change):

```sh
kubectl create job --from=cronjob/keycloak-db-dump manual-$(date +%Y%m%d-%H%M) -n keycloak --context admin@<env>-homelab
kubectl logs job/manual-<...> -c upload -n keycloak --context admin@<env>-homelab
```

List the dumps in the bucket with the credentials of the `keycloak-db#<env>` 1Password item (`aws --endpoint-url https://fiona.home.iseja.net:9000 s3 ls s3://<env>-keycloak-db`, with `AWS_DEFAULT_REGION=default`).

## Restore

Restoring takes the newest (or a chosen) dump and loads it into an empty `keycloak` database. It was verified by restoring a dump into a scratch database in `qa` (101 tables, the same realm and user counts as the source). A full drill, including logging in with an existing WebAuthn credential, is part of the restore work of [#1826](https://github.com/isejalabs/homelab/issues/1826) and not covered here yet.

1. **Get an empty database.** For a lost cluster let Flux recreate it (CloudNativePG runs `initdb` with the `keycloak` database and owner). For a damaged but running database, delete the `Cluster` and its PVC, plus the Retain `PersistentVolume` and the Longhorn volume, and let Flux recreate it.
2. **Make sure Keycloak is not writing.** Scale the Keycloak `StatefulSet` to 0, or restore before Keycloak ever starts against the new database.
3. **Run the restore job** below, set `BUCKET` and `DUMP_KEY` (the object name from the listing). `--clean --if-exists` also covers a database in which Keycloak already created its schema.
4. **Restart Keycloak** (delete its pods) so it picks up the restored data, then sign in.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: keycloak-db-restore
  namespace: keycloak
spec:
  backoffLimit: 0
  template:
    spec:
      initContainers:
        - name: download
          image: public.ecr.aws/aws-cli/aws-cli:2.38.5
          command: ["/bin/sh", "-ec", "aws s3 cp \"s3://${BUCKET}/${DUMP_KEY}\" /dump/keycloak.dump --only-show-errors"]
          env:
            - {name: AWS_ACCESS_KEY_ID, valueFrom: {secretKeyRef: {name: keycloak-db-backup, key: AWS_ACCESS_KEY_ID}}}
            - {name: AWS_SECRET_ACCESS_KEY, valueFrom: {secretKeyRef: {name: keycloak-db-backup, key: AWS_SECRET_ACCESS_KEY}}}
            - {name: AWS_DEFAULT_REGION, value: default}
            - {name: AWS_ENDPOINT_URL, value: "https://fiona.home.iseja.net:9000"}
            - {name: AWS_REQUEST_CHECKSUM_CALCULATION, value: when_required}
            - {name: AWS_RESPONSE_CHECKSUM_VALIDATION, value: when_required}
            - {name: BUCKET, value: <env>-keycloak-db}
            - {name: DUMP_KEY, value: keycloak-<timestamp>.dump}
            - {name: HOME, value: /tmp}
          volumeMounts: [{name: dump, mountPath: /dump}]
      containers:
        - name: restore
          image: ghcr.io/cloudnative-pg/postgresql:18.6-system-trixie
          command: ["pg_restore", "--clean", "--if-exists", "--no-owner", "--exit-on-error", "--dbname=keycloak", "/dump/keycloak.dump"]
          env:
            - {name: PGHOST, valueFrom: {secretKeyRef: {name: keycloak-db-app, key: host}}}
            - {name: PGPASSWORD, valueFrom: {secretKeyRef: {name: keycloak-db-app, key: password}}}
            - {name: PGUSER, valueFrom: {secretKeyRef: {name: keycloak-db-app, key: username}}}
          volumeMounts: [{name: dump, mountPath: /dump}]
      restartPolicy: Never
      securityContext: {runAsNonRoot: true, runAsUser: 26, runAsGroup: 26, fsGroup: 26, seccompProfile: {type: RuntimeDefault}}
      volumes:
        - {name: dump, emptyDir: {}}
```

## Why a dump and no WAL archiving

The first design archived WAL and took base backups with the Barman Cloud plugin. In `qa` that failed within hours: the backup credentials did not exist yet, archiving failed, and PostgreSQL does not recycle WAL it has not archived, so unarchived WAL filled the 1Gi volume and stopped the database. A separate WAL volume would only move the failure. A backup target that is down must never be able to take the live database down, so:

- The cluster has the annotation `cnpg.io/skipWalArchiving: enabled`, which sets `archive_mode = off`. WAL is recycled normally, whatever the state of the backup target. CloudNativePG documents this annotation as "use at your own risk" and it needs a restart of the instance; it was verified on `qa` (`archive_mode = off`, cluster ready).
- The database holds only a few MB (a fresh one is 13 MB), so a full dump is cheap and the 24 h recovery point is the daily schedule itself. There is no point-in-time recovery.
- The remaining WAL is kept small on purpose: `wal_keep_size 64MB` (CloudNativePG defaults to 512MB, half of this volume), `max_wal_size 256MB`, `min_wal_size 64MB`, `wal_compression on`, `wal_level replica`. The volume stays at 1Gi.

This differs from point 6 of [ADR 0016](decisions/0016-identity-and-web-sso.md) (CloudNativePG base backups and WAL archiving to RustFS); the ADR is a historical record and is not rewritten. The reasoning above is the current state.

## Known caveats

- **No alert on failed dumps yet.** Check the CronJob after changes and during the soak in `qa`. Alerting is tracked with the observability work.
- **Dumps are not encrypted.** They contain password hashes and MFA secrets and sit unencrypted in a bucket that only the scoped `<env>-keycloak-db` user can access. Encrypting them (for example with `age`) is a possible follow-up.
- **Not tested with a live `--clean` restore** over a database that Keycloak has already initialized; the scratch-database restore is. Treat the first real restore as the drill.
- **RustFS must be reachable at 02:00.** A failed run keeps the previous dumps; the next day's run tries again.
