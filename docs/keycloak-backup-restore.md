---
status: current
---

# Keycloak Database Backup & Restore

**Choose a task:** check or trigger a backup under [Daily tasks](#daily-tasks); recover the database under [Restore](#restore).

**On this page:** [Overview](#overview) · [How it works](#how-it-works) · [Daily tasks](#daily-tasks) · [Restore](#restore) · [WebAuthn after a restore](#webauthn-after-a-restore) · [Why a dump and no WAL archiving](#why-a-dump-and-no-wal-archiving) · [Known caveats](#known-caveats)

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
- **Where it runs**: only in the environments that register the units (currently `dev`, `qa` and `rebuild`; see [`sets/soaking`](../k8s/bootstrap/cluster/flux/sets/soaking/kustomization.yaml)).

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

Restoring takes the newest (or a chosen) dump and loads it into an empty `keycloak` database. It was verified twice: by restoring a dump into a scratch database in `qa`, and by a full drill in `rebuild` with a `qa` dump (see [Restore drill](#restore-drill)).

1. **Get an empty database.** For a lost cluster let Flux recreate it (CloudNativePG runs `initdb` with the `keycloak` database and owner). For a damaged but running database, delete the `Cluster` and its PVC, plus the Retain `PersistentVolume` and the Longhorn volume, and let Flux recreate it.
2. **Make sure Keycloak is not writing.** Scale the Keycloak Operator (`kubectl scale deploy keycloak-operator -n keycloak --replicas=0`) and then the Keycloak `StatefulSet` to 0, or restore before Keycloak ever starts against the new database. The operator is scaled first so it cannot bring the `StatefulSet` back; scale it up again afterwards and it recreates Keycloak by itself.
3. **Run the restore job** below, set `BUCKET` and `DUMP_KEY` (the object name from the listing). `--clean --if-exists` also covers a database in which Keycloak already created its schema.
4. **Start Keycloak again** (scale the operator back to 1; it recreates the `StatefulSet`, or delete the pod if Keycloak was left running) so it picks up the restored data, then sign in.

A dump taken in another environment can be restored too: copy it into the target's `<env>-keycloak-db` bucket first (each environment's user only reaches its own bucket), then restore as above. The realm content and the Keycloak master-realm users come from the dump, **including the master admin password of the source environment**, not the `keycloak-bootstrap-admin#<env>` one of the target.

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

## Restore drill

Done on 2026-10-26 in `rebuild` ([#1920](https://github.com/isejalabs/homelab/issues/1920)), restoring the newest `qa` dump (282 KB) into a new `rebuild` database over a schema that Keycloak had already initialized, so `--clean --if-exists` was exercised for real:

| Step | Result |
| --- | --- |
| Register in `rebuild`, apply `rustfs-keycloak-db`, create `keycloak-bootstrap-admin#rebuild` | Units reconciled; Keycloak ready about 3 min after the database (first start creates the schema) |
| Before the restore | 101 tables, realm `master` only |
| Restore job (`download` 9 s, `pg_restore` 21 s) | Complete in 56 s including pod start; no errors with `--exit-on-error` |
| After the restore | 101 tables; realms `master`, `iseja`, `admin`; one imported user in each of `iseja` and `admin` |
| Start Keycloak again | Ready within about 1 min; OIDC discovery answers 200 for all three realms |
| Login | Pending the owner's browser check, see below |

Observations:

- **Tables and realms match the source**, but the restore cannot say anything about credentials Keycloak does not store. `sebi` and `sebi-adm` are federated: their password is checked against UCS, so Keycloak holds no local credential for them and "an existing credential" is only a UCS password until MFA exists ([#1827](https://github.com/isejalabs/homelab/issues/1827)). The only credential row in the dump is the master admin password.
- **WebAuthn is not exercised yet.** Nobody has enrolled one anywhere, so the part of the plan "login with an existing WebAuthn credential" stays open until #1827; see [WebAuthn after a restore](#webauthn-after-a-restore) for what this drill could not show even then and for the rehearsal to repeat.
- **No sessions to test.** There are no applications yet, so the drill does not show what happens to existing app sessions; per the table under [Overview](#overview) they are lost anyway.
- **Hostname and TLS** come from the target's `Keycloak` resource (`rebuild-auth.rebuild.iseja.net`) and shared Gateway wildcard certificate (now Let's Encrypt production), not from the dump.

## WebAuthn after a restore

A restore must bring back more than tables, realms and OIDC discovery: a user who enrolled a WebAuthn key (passkey, YubiKey) has to be able to log in with it afterwards. That is not shown by the [restore drill](#restore-drill) and cannot be shown before MFA is rolled out ([#1827](https://github.com/isejalabs/homelab/issues/1827)). It is tracked in [#1943](https://github.com/isejalabs/homelab/issues/1943), which is blocked by #1827 for the credential part. This section records what is already known, the proposed drill setup and the rehearsal to run once a credential exists.

### What is known

- **The relying-party ID is not set by the realm module.** The module [`keycloak-realm`](https://github.com/isejalabs/terraform-modules/tree/keycloak-realm-v0.2.0/modules/keycloak-realm) (version used by [`terragrunt/_envcommon/keycloak-realm.hcl`](../terragrunt/_envcommon/keycloak-realm.hcl)) creates the `web_authn_policy` of every realm with `relying_party_entity_name`, the signature algorithms and the user-verification requirement only, and no `relying_party_id`. The Keycloak documentation for the policy says: if the Relying Party ID is blank, Keycloak uses the host part of its base URL. The RP ID is therefore the Keycloak hostname of the environment:

| Environment | Keycloak hostname (= effective RP ID) |
| --- | --- |
| `dev` | `dev-auth.dev.iseja.net` |
| `qa` | `qa-auth.qa.iseja.net` |
| `rebuild` | `rebuild-auth.rebuild.iseja.net` |
| `prod` | `auth.iseja.net` (not deployed yet) |

- **A credential is bound to its RP ID.** A WebAuthn credential registered for one RP ID is not valid for another (W3C WebAuthn). Both realms, `iseja` and `admin`, are served from the same hostname, so they share the RP ID of their environment.
- **Not yet confirmed on a live instance:** that the RP ID field of the WebAuthn policy is blank in the admin console of each realm after `keycloak-realm` was applied (step 1 of the [rehearsal](#rehearsal)), and that the dump carries the WebAuthn credential rows of LDAP-federated users (the table under [Overview](#overview) assumes it).

### What a restore under a different hostname cannot prove

- A dump restored into another environment (the `qa` dump into `rebuild`, as in the drill) carries credentials registered for `qa-auth.qa.iseja.net`. A browser will not offer them on `rebuild-auth.rebuild.iseja.net`, so a failed login there says nothing about the restore, and a successful one is impossible. Such a restore proves tables, realms, users and discovery, and nothing about credential portability.
- The same holds for the issuer: it contains the hostname, so tokens and client registrations of the source do not carry over to a target with another hostname.
- A credential enrolled in `rebuild` after the restore proves only that enrolment works there.

### Drill setup

To keep the RP ID (and the issuer) the drill has to answer on the hostname the credential was registered for. Options:

| Option | What it is | Assessment |
| --- | --- | --- |
| A. Restore in place, same environment | Enroll the test credential in an environment, take a dump, empty the database as in [Restore](#restore) step 1, restore, start Keycloak, log in on the unchanged hostname | Needs nothing new and keeps RP ID and issuer. Destructive for that environment, which is acceptable in `dev` (or `qa`) while no real users depend on it. **Proposed** |
| B. Isolated recovery instance on the real hostname | A second Keycloak and database restored from the dump, answering on the production hostname for one test client only (split DNS or a hosts-file entry on that client, plus a certificate for the name) | Needed for a prod rehearsal that must not touch the running instance. Not tried; the certificate and secure-context behaviour with a staging or private certificate are open questions. Revisit when `prod` exists |
| C. Explicit, environment-independent RP ID | Set `relying_party_id` in the module to a shared parent domain so a credential works in every environment | Not adopted: it is a design change that makes credentials portable between `dev` and `prod`, and it has not been checked that Keycloak accepts a parent domain of the host. Belongs with the hostname work in [#1946](https://github.com/isejalabs/homelab/issues/1946) if wanted at all |

### Rehearsal

Run it once #1827 has rolled out the WebAuthn flows. The setup (A) and the environment are the owner's decision; the owner also holds the authenticator.

1. **Before enrolling:** open *Authentication* → *Policies* → *WebAuthn Policy* in each realm and note whether *Relying Party ID* is blank. Enroll a test credential for a federated test user. Keycloak builds the WebAuthn user handle from the internal user ID, which for users of an external federation is a storage ID that can exceed the 64-byte limit of the specification (see the WebAuthn chapter of the Keycloak server administration guide); if enrolment fails for a federated user, that is a finding for #1827 and not for the restore.
2. **Enroll** one credential in each realm: `admin` (the `sebi-adm` account, or a test account in `idm-admins`) and `iseja` (a test account in `idm-users`). Log in once with each to prove they work before the restore.
3. **Dump:** trigger a manual dump ([Daily tasks](#daily-tasks)) after the enrolments and note the object name.
4. **Restore** the dump on the same hostname, following [Restore](#restore): empty database, operator and Keycloak stopped, restore job, start Keycloak.
5. **Log in** in each realm with password and the enrolled credential. Expected: success.
6. **Also check:** the user and group claims (client scope evaluation for a test client, or the first real client), that federation to UCS still answers, and that the emergency administrator of `master` can sign in with the password of the dump ([break-glass](keycloak-break-glass.md)).
7. **Optional negative control:** restore the same dump into another environment and note that the credential is not offered there. This documents the limit above instead of discovering it during an incident.
8. **Record** the result in the table below and in the issue, including the Keycloak version and the environment.

| Realm | Result | Date | Environment |
| --- | --- | --- | --- |
| `iseja` | Pending, blocked by #1827 | | |
| `admin` | Pending, blocked by #1827 | | |

If the rehearsal fails, or the owner decides not to run it, the consequence stays as stated under [Overview](#overview): users enrolled since the last dump, or all of them when the credential does not survive, enroll again, and for the `admin` realm that needs [break-glass access](keycloak-break-glass.md). That consequence has to be accepted explicitly for each realm; it is not accepted yet.

## Why a dump and no WAL archiving

The first design archived WAL and took base backups with the Barman Cloud plugin. In `qa` that failed within hours: the backup credentials did not exist yet, archiving failed, and PostgreSQL does not recycle WAL it has not archived, so unarchived WAL filled the 1Gi volume and stopped the database. A separate WAL volume would only move the failure. A backup target that is down must never be able to take the live database down, so:

- The cluster has the annotation `cnpg.io/skipWalArchiving: enabled`, which sets `archive_mode = off`. WAL is recycled normally, whatever the state of the backup target. CloudNativePG documents this annotation as "use at your own risk" and it needs a restart of the instance; it was verified on `qa` (`archive_mode = off`, cluster ready).
- The database holds only a few MB (a fresh one is 13 MB), so a full dump is cheap and the 24 h recovery point is the daily schedule itself. There is no point-in-time recovery.
- The remaining WAL is kept small on purpose: `wal_keep_size 64MB` (CloudNativePG defaults to 512MB, half of this volume), `max_wal_size 256MB`, `min_wal_size 64MB`, `wal_compression on`, `wal_level replica`. The volume stays at 1Gi.

This differs from point 6 of [ADR 0016](decisions/0016-identity-and-web-sso.md) (CloudNativePG base backups and WAL archiving to RustFS); the ADR is a historical record and is not rewritten. The reasoning above is the current state.

## Known caveats

- **No alert on failed dumps yet.** Check the CronJob after changes and during the soak in `qa`. Alerting is tracked with the observability work.
- **Dumps are not encrypted.** They contain password hashes and MFA secrets and sit unencrypted in a bucket that only the scoped `<env>-keycloak-db` user can access. Encrypting them (for example with `age`) is a possible follow-up.
- **RustFS must be reachable at 02:00.** A failed run keeps the previous dumps; the next day's run tries again.
