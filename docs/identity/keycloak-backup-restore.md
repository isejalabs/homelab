---
status: current
---

# Keycloak Database Backup & Restore

**Choose a task:** check or trigger a backup under [Daily tasks](#daily-tasks); set up the encryption key under [Encryption key](#encryption-key-age); set up the alert under [Alerting](#alerting); recover the database under [Restore](#restore); restore a dump taken in another environment under [A dump from another environment](#a-dump-from-another-environment).

**On this page:** [Overview](#overview) · [How it works](#how-it-works) · [Daily tasks](#daily-tasks) · [Encryption key](#encryption-key-age) · [Alerting](#alerting) · [Restore](#restore) · [Restore drill](#restore-drill) · [Upgrading PostgreSQL](#upgrading-postgresql) · [Why a dump and no WAL archiving](#why-a-dump-and-no-wal-archiving) · [Known caveats](#known-caveats)

## At a glance

| | |
| --- | --- |
| When to use | The Keycloak database is lost, broken or holds wrong content, or a dump from another environment has to be loaded. To check or trigger a backup see [Daily tasks](#daily-tasks). For signing in while Keycloak or UCS is down see [`keycloak-break-glass.md`](keycloak-break-glass.md) |
| Prerequisites | `just`, `kubectl`, `flux`, `gum` and `jq` locally, the kube context `admin@<env>-homelab`, a dump in the `<env>-keycloak-db` bucket ([list them](#restore)) and, for an encrypted dump (`*.dump.age`), the age private key ([where it lives](#encryption-key-age)) |
| Steps | [Restore](#restore): `just backup::keycloak::restore -e <env> --identity <key file>`, four phases (select and verify, stop the writers, swap, start again). Expected output is recorded for the drills: [Restore drill](#restore-drill) |
| Verify | [After the script](#restore): sign in (`master` realm) and check the realms and a user |
| Rollback | [Roll back](#roll-back): possible until the old database `keycloak_before_<timestamp>` is dropped |
| Last exercised | The script on 2026-10-28 in `rebuild` ([#1938](https://github.com/isejalabs/homelab/issues/1938)); the manual procedure on 2026-10-26 in `rebuild` ([#1920](https://github.com/isejalabs/homelab/issues/1920)). The login check is pending the owner's browser check, and the roll back and a dump with a failing `pg_restore` are not drilled |

## Overview

Keycloak (see [#1826](https://github.com/isejalabs/homelab/issues/1826)) keeps its state in a single-instance [CloudNativePG](https://cloudnative-pg.io/) cluster, `keycloak-db` in the `keycloak` namespace ([`k8s/apps/identity/keycloak/`](../../k8s/apps/identity/keycloak/)). It is backed up with a **daily logical dump** (`pg_dump`), encrypted with [age](https://github.com/FiloSottile/age) and uploaded to a per-environment bucket on `fiona`, the S3-compatible NAS (`<env>-keycloak-db`).

What is in the database, and what a restore from the latest dump loses:

| Content | After a restore from a dump up to 24 h old |
| --- | --- |
| Realm configuration | Comes back with the dump; once realms are managed as code it also comes back from Git |
| Users imported from UCS | Come back with the dump; re-synced from UCS anyway |
| Sessions | Lost for anything created since the dump; users sign in again |
| MFA enrollments (WebAuthn keys, TOTP secrets) | Lost for anything enrolled since the dump; those users must **enroll again**, which for the `admin` realm needs [break-glass access](keycloak-break-glass.md) |

The accepted target is a recovery point of 24 h (the design plan, [`docs/plans/2026-10-identity-claude.md`](../plans/2026-10-identity-claude.md)): a database loss is a break-glass situation anyway, so the last day of sessions and new enrollments may be lost.

**`prod` accepts the same target.** Daily dumps and a 24 h recovery point (no point-in-time recovery) meet the requirement for `prod`: the owner confirmed on 2026-11-01 that even the loss of all dumps is recoverable, because the realm configuration is code and the few users re-enroll their MFA. This holds while the user base stays this small; revisit it before Keycloak serves other people.

## How it works

- **Schedule**: the `keycloak-db-dump` `CronJob` runs every day at 02:00 (`Europe/Berlin`), see [`cronjob-dump.yaml`](../../k8s/apps/identity/keycloak/base/cronjob-dump.yaml).
- **Two steps in one pod**: an init container runs `pg_dump --format=custom` against the read-write service `keycloak-db-rw` with the application credentials from the `keycloak-db-app` secret (created by CloudNativePG), writing to an `emptyDir`. A third step, `fetch-age`, puts the pinned `age` binary next to it ([why it is downloaded](#why-age-is-downloaded)). The main container encrypts the file to the age public key(s) in `AGE_RECIPIENTS`, uploads it as `keycloak-<UTC timestamp>.dump.age` with the AWS CLI, deletes everything but the newest 14 dumps and finally pings the [heartbeat](#alerting) where one is configured. A plaintext dump is never uploaded: without a valid public key the job fails before the upload. A failed dump leaves nothing to upload, so a broken dump never replaces a good one. The init container also runs `pg_restore --list` on the finished file, so a dump whose table of contents cannot be read fails the job before the upload (this proves the archive is readable, not that a restore succeeds; that is what the [restore drill](#restore-drill) is for).
- **Credentials and bucket**: the access key comes from the `keycloak-db-backup` secret, delivered by External Secrets from the 1Password item `keycloak-db#<env>`. The bucket `<env>-keycloak-db`, its scoped RustFS user and that item are created by the Terragrunt unit `rustfs-keycloak-db` (see [`terragrunt/README.md`](../../terragrunt/README.md)). **Apply that unit before the Flux units are registered in an environment.**
- **Client version**: `pg_dump` must be at least as new as the server. The server image is pinned explicitly (`spec.imageName` in [`cluster.yaml`](../../k8s/apps/identity/keycloak/base/cluster.yaml), tag and digest) and a kustomize replacement in [`kustomization.yaml`](../../k8s/apps/identity/keycloak/base/kustomization.yaml) copies that value into the dump job, so the two cannot drift apart. The restore script builds its Job from the dump CronJob, so it restores with the same image. How the image is bumped: [Upgrading PostgreSQL](#upgrading-postgresql).
- **Where it runs**: only in the environments that register the units (currently `dev`, `qa` and `rebuild`; see [`sets/soaking`](../../k8s/bootstrap/cluster/flux/sets/soaking/kustomization.yaml)).

## Daily tasks

Check the last runs (an alert is described under [Alerting](#alerting); this is the manual check):

```sh
kubectl get cronjob,job -n keycloak --context admin@<env>-homelab
```

Trigger a backup now (for example before a risky change):

```sh
kubectl create job --from=cronjob/keycloak-db-dump manual-$(date +%Y%m%d-%H%M) -n keycloak --context admin@<env>-homelab
kubectl logs job/manual-<...> -c upload -n keycloak --context admin@<env>-homelab
```

List the dumps in the bucket with `just backup::keycloak::list -e <env>`, or by hand with the credentials of the `keycloak-db#<env>` 1Password item (`aws --endpoint-url https://fiona.home.iseja.net:9000 s3 ls s3://<env>-keycloak-db`, with `AWS_DEFAULT_REGION=default`).

## Encryption key (age)

The dumps hold password hashes and MFA secrets, so each one is encrypted before it leaves the cluster. The scheme is asymmetric on purpose: the job only knows the **public** key, so a leaked job, Secret or bucket credential cannot decrypt anything, and the private key is needed only on the day a dump is restored.

**Setup, once** (a dedicated key, not the SOPS key of this repository):

1. Generate the key pair on your workstation, offline: `age-keygen -o keycloak-db.agekey` (`brew install age`). The file holds the private key; the public key (`age1…`) is printed and can be shown again with `age-keygen -y keycloak-db.agekey`.
2. Store the **private key** in 1Password in a vault that External Secrets and the cluster cannot read, not the `K8S` vault (for example your personal vault, item `keycloak-db age key`), and keep a second copy offline. A lost private key makes every dump unreadable.
3. Put the **public key** into `AGE_RECIPIENTS` in [`cronjob-dump.yaml`](../../k8s/apps/identity/keycloak/base/cronjob-dump.yaml). It is not secret and is committed. The value accepts several space separated keys, which is how a second recovery key or a rotation would be added. The base value `TODO-add-the-age-public-key` makes the job fail on purpose until this is done.
4. Delete `keycloak-db.agekey` from the workstation once both copies exist.

**One key for all environments.** A dump from another environment is a documented flow ([A dump from another environment](#a-dump-from-another-environment)) and then needs only one private key. `prod` can get its own key later by overriding `AGE_RECIPIENTS` in `envs/prod/` the way the bucket name is overridden.

**Check it works**: trigger a backup ([Daily tasks](#daily-tasks)), then `just backup::keycloak::list -e <env>` shows a `keycloak-….dump.age` object. To read it without a restore: download it and run `age -d -i keycloak-db.agekey keycloak-….dump.age | pg_restore --list`.

**Rotation.** Add the new public key to `AGE_RECIPIENTS` (and drop the old one in a later change). Dumps already in the bucket stay readable only with the key they were encrypted to, so keep the old private key until the last dump encrypted to it has been pruned (14 days at the daily schedule).

**Plain dumps.** Dumps taken before the encryption (`keycloak-….dump`) restore without `--identity`; they age out with the retention.

**Restore.** Pass the private key to the restore script, for example straight from 1Password without writing it to disk:

```sh
just backup::keycloak::restore -e <env> --identity <(op read 'op://Private/keycloak-db age key/private key')
```

The script puts the key into a temporary Secret `keycloak-db-restore-identity-<timestamp>` that only the restore Job mounts, and deletes it right after that Job ended (also if the run is aborted). So the private key is in the cluster, and in etcd, for the minutes of the scratch restore and nowhere else. If you do not want that, decrypt on the workstation instead: download the object, `age -d` it, and load the plain dump yourself.

### Why age is downloaded

No image this job uses ships `age`: the PostgreSQL image has `openssl` and `gpg`, the aws-cli image has `gpg` and `curl`, neither has `age`. Instead of a third-party image (the encrypting step sees the plaintext dump, so its image has to be trusted) or an image built here (a new pipeline for one binary), the `fetch-age` init container downloads the pinned release from GitHub, checks its sha256 and unpacks it into an `emptyDir`. Consequences:

- The job needs `github.com` at 02:00 as well as RustFS. If it is unreachable the job fails, nothing is uploaded and the next day tries again; the [alert](#alerting) catches it.
- Only `linux/amd64` is supported (the clusters are amd64); the step fails on another architecture.
- **Bump `age` by hand**: Renovate cannot update the hash. Change `version` and `sha256` together in `fetch-age`, taking the digest of the `age-<version>-linux-amd64.tar.gz` asset from `gh api repos/FiloSottile/age/releases/tags/<version> --jq '.assets[] | select(.name | endswith("linux-amd64.tar.gz")) | .digest'`. The restore script reuses the same step, so it follows.

## Alerting

A dump that fails, or never runs (the CronJob suspended, a controller problem), must not go unnoticed. Two layers:

| Layer | Catches | Covers |
| --- | --- | --- |
| **Heartbeat** ([healthchecks.io](https://healthchecks.io/)) | A dump that did not complete and upload by the time the check expects it, including a job that never started | Every environment that has a check |
| **Checkmk** `kube_cronjob_status` | A CronJob whose latest job failed | Only the environments feeding a `*_k8s` CMC site, see below |

**Heartbeat.** After the upload and the prune the job pings the URL in the Secret `keycloak-db-heartbeat`; if the run fails inside the upload container it pings `<URL>/fail`. A failure in the earlier init containers (dump, verification, `fetch-age`) sends no `/fail`, because the upload container never starts; it is caught by the missing success ping once the grace time is over. Setup per environment:

1. In healthchecks.io create a check, schedule `period` 1 day and `grace time` a few hours (the job starts at 02:00 and takes minutes), with the notification channel you read.
2. Create the 1Password item `keycloak-db-heartbeat#<env>` in the `K8S` vault with the field `HEARTBEAT_URL` set to the check's ping URL (no trailing slash).
3. Register the Secret in the environment: copy [`externalsecret-heartbeat.yaml`](../../k8s/apps/identity/keycloak/envs/qa/externalsecret-heartbeat.yaml) into `envs/<env>/`, change the key to `keycloak-db-heartbeat#<env>` and list it under `resources:`. `qa` has it; `dev` and `rebuild` have none on purpose (the Secret reference is optional, no URL means no ping), `rebuild` is torn down too often for a dead man's switch. Add it to `prod` when Keycloak goes there.
4. Check the first run in the healthchecks.io log. A ping to a URL with a wrong UUID is answered `200 OK` as well ("not found" is a 200 for UUID endpoints), so a typo does not show as an error in the job log; the check staying grey in the UI does.
5. **Test the alert**: `kubectl patch cronjob keycloak-db-dump -n keycloak --context admin@<env>-homelab -p '{"spec":{"suspend":true}}'`, wait for period plus grace, expect the notification, then set `suspend` back to `false` (Flux does not undo a manual suspend, see [Why Flux is suspended](#why-flux-is-suspended)).

The ping URL is a credential of the check (anyone with it can mark it up), which is why it lives in 1Password and not in Git. The free "Hobbyist" plan allows 20 checks.

**Checkmk.** The Kubernetes agent already collects CronJobs ([`checkmk-agent` README](../../k8s/apps/monitoring/checkmk-agent/README.md)). The Checkmk check [`kube_cronjob_status`](https://checkmk.com/integrations/kube_cronjob_status) reports the status of a CronJob's latest job (completed, running, pending, failed) and the time since its last successful schedule and completion; its only documented threshold is for a job that stays pending, so it flags a **failed** job but, as documented, not a job that never ran. It runs only where the Kubernetes data arrives: the sites `qa_k8s` (notifications on) and `prod_k8s` (notifications off, [#1901](https://github.com/isejalabs/homelab/issues/1901)), both CMC, see [`monitoring-sites.md`](../reference/monitoring-sites.md). `dev` and `rebuild` have no active site, and `mk-job` does not apply (it wraps cron jobs on a host). Not verified on the live sites: that the CronJob host and the service exist for `keycloak-db-dump` and that a failed dump notifies.

**Network.** The job reaches RustFS on `fiona`, `github.com` (`fetch-age`) and `hc-ping.com`. A future egress policy for the `keycloak` namespace ([#1945](https://github.com/isejalabs/homelab/issues/1945)) has to allow all three.

## Restore

> [!WARNING]
> Keycloak is down from phase 2 (stop the writers) until phase 4 has finished.

Restoring takes the newest (or a chosen) dump and swaps it in for the live `keycloak` database with [`scripts/keycloak-db-restore.sh`](../../scripts/keycloak-db-restore.sh). Nothing is deleted: the dump is restored into a scratch database next to the live one, checked, and the two are swapped by renaming once everything that writes has been stopped. The previous database stays in the cluster until you drop it.

You need `just`, `kubectl`, `flux`, `gum` and `jq` locally and the kube context `admin@<env>-homelab`. A restore always names its environment:

```sh
just backup::keycloak::list -e <env>                       # dumps in the bucket: key, last modified, size
just backup::keycloak::restore -e <env> --identity <key file>                  # newest dump
just backup::keycloak::restore -e <env> --identity <key file> --dump <key>     # a chosen dump
```

The recipes pass their flags to the script, so `scripts/keycloak-db-restore.sh -e <env> [--list] [--dump <key>] [--identity <key file>] [-y]` does the same without `just`. `--identity` is the [age private key](#encryption-key-age) and is only needed for an encrypted (`*.age`) dump; the script refuses to start without it, before anything is changed.

What the script does, in this order (the first change to the live database is the rename in phase 3):

| Phase | What happens | Keycloak |
| --- | --- | --- |
| 1. Select and verify | Lists the bucket, picks the dump (the newest unless `--dump`), creates `keycloak_restore` and loads the dump into it with a Job built from the `keycloak-db-dump` CronJob (same images, credentials and bucket). A dump that does not restore stops here. Prints tables, realms and users of the live and the restored database side by side and asks for confirmation. | running |
| 2. Stop the writers | Suspends the Flux `Kustomization`s `keycloak` and `keycloak-operator` and the `keycloak-db-dump` CronJob (and waits for a running dump), scales the operator and the Keycloak `StatefulSet` to 0, waits until no client is connected to the database. | down |
| 3. Swap | In one transaction: `keycloak` becomes `keycloak_before_<timestamp>`, `keycloak_restore` becomes `keycloak`. | down |
| 4. Start again | Resumes Flux, scales the operator back, restores the CronJob's suspend flag and waits for the `Keycloak` resource to be `Ready`. | starting |

If anything fails between phase 2 and the swap, the script resumes Flux, the operator and the CronJob and the live database is untouched. The Jobs of a run are named `keycloak-db-restore-*` and are removed after a day.

A lost or broken **database instance** (not just its content) is recreated first, see [below](#recreate-a-lost-or-broken-instance); the script then restores into the fresh, empty `keycloak` database like into any other.

After the script:

1. **Sign in** (`master` realm, see [break-glass access](keycloak-break-glass.md)) and check the realms and a user.
2. **Drop the old database** when you are satisfied. The script prints the command; it needs the primary, `kubectl get cluster keycloak-db -n keycloak -o jsonpath='{.status.currentPrimary}'`, and then `psql -U postgres -c 'drop database keycloak_before_<timestamp>;'` inside its `postgres` container. Each kept database takes a few MB of the 1Gi volume.

### Roll back

Until the old database is dropped the swap can be undone. Stop the writers like phase 2 does (suspend the two `Kustomization`s and the CronJob, scale the operator and the `StatefulSet` to 0), then in the primary's `postgres` container:

```sql
begin;
alter database keycloak rename to keycloak_discarded;
alter database keycloak_before_<timestamp> rename to keycloak;
commit;
```

and start everything again (`flux resume kustomization keycloak-operator keycloak`, scale the operator back, un-suspend the CronJob).

### Recreate a lost or broken instance

Only needed when the PostgreSQL instance itself is gone or cannot start; a database with wrong content does not need it. For a lost cluster let Flux recreate it (CloudNativePG runs `initdb` with the `keycloak` database and owner). For a damaged one, suspend the two Flux `Kustomization`s first, then delete the `Cluster` and its PVC, plus the Retain `PersistentVolume` and the Longhorn volume, and resume Flux so it recreates the cluster. Then run the script as above.

### A dump from another environment

Copy the dump into the target's `<env>-keycloak-db` bucket first (each environment's user only reaches its own bucket), then restore it as above. What comes with the dump, which is the source environment's state and not the target's:

- **Master admin password.** The `master` realm, including its admin account and password, comes from the dump. The target's `keycloak-bootstrap-admin#<env>` item is not used: Keycloak applies the bootstrap variables only on the first start against an empty database. After the restore the 1Password item of the *source* environment holds the password that works ([break-glass access](keycloak-break-glass.md#where-the-credential-lives)); update the target's item or rotate the password.
- **Realms and clients.** Realm settings, clients and their secrets, and the realm signing keys are database content and come with the dump. The hostname and certificate do not: they come from the target's `Keycloak` resource.
- **UCS federation.** The federation settings of the realms `iseja` and `admin` (connection, bind credential) come from the dump too. Whether the next apply of the Terragrunt unit [`keycloak-realm`](keycloak-realms.md) of the target is clean after a restore from another environment has not been tried.
- **MFA enrollments.** WebAuthn keys and TOTP secrets in the dump belong to users of the source environment. A WebAuthn key is registered for a relying-party ID that normally follows the hostname, so keys enrolled in another environment are not expected to work in the target; not tried, see [#1943](https://github.com/isejalabs/homelab/issues/1943).

> [!WARNING]
> A dump holds password hashes, MFA secrets, client secrets and realm keys, so treat it as a secret of its source environment: a `prod` dump restored into `dev` hands `dev` the `prod` realm keys and client secrets.

### Why Flux is suspended

The earlier procedure scaled the operator and the `StatefulSet` down by hand and did not touch Flux, which could undo that while the recovery was still running:

| Part | Can it undo the scale-down? | Basis |
| --- | --- | --- |
| Operator `Deployment` (in Git, `keycloak-operator` `Kustomization`, interval 1 h, 10 min in `rebuild`) | **Yes**, at the next reconcile of that `Kustomization` | A plain-manifest `Kustomization` does real drift correction; observed live for other apps in `dev` and `rebuild`, see the header of [`kopiur-restore.sh`](../../scripts/kopiur-restore.sh). Observed for this `Deployment` too in the [drill with the script](#with-keycloak-db-restoresh): a manual scale to 0 was back at 1 right after `flux reconcile kustomization keycloak-operator`. |
| Keycloak `StatefulSet` (owned by the operator, not in Git) | Flux does not touch it, but a revived operator reconciles it back to `spec.instances: 1` | Observed in the same drill: the `StatefulSet`, scaled to 0 by the script, was recreated at 1 replica about 10 s after the operator came back |
| `keycloak-db-dump` `CronJob` (02:00) | Nothing scales it; it simply runs if the restore is in progress at 02:00 and dumps a half-restored database | The earlier guide did not suspend it |

So the script suspends all three and restores their state itself afterwards: a suspend flag set with `kubectl patch` is not in the manifest, so Flux would not clear it, and the `Deployment`'s replicas would only come back at the next reconcile.

## Restore drill

### With the manual procedure

This drill predates the script: it used the earlier manual procedure (delete the cluster, scale down by hand, apply a copied restore Job). Done on 2026-10-26 in `rebuild` ([#1920](https://github.com/isejalabs/homelab/issues/1920)), restoring the newest `qa` dump (282 KB) into a new `rebuild` database over a schema that Keycloak had already initialized, so `--clean --if-exists` was exercised for real:

| Step | Result |
| --- | --- |
| Register in `rebuild`, apply `rustfs-keycloak-db`, create `keycloak-bootstrap-admin#rebuild` | Units reconciled; Keycloak ready about 3 min after the database (first start creates the schema) |
| Before the restore | 101 tables, realm `master` only |
| Restore job (`download` 9 s, `pg_restore` 21 s) | Complete in 56 s including pod start; no errors with `--exit-on-error` |
| After the restore | 101 tables; realms `master`, `iseja`, `admin`; one imported user in each of `iseja` and `admin` |
| Start Keycloak again | Ready within about 1 min; OIDC discovery answers 200 for all three realms |
| Login | Pending the owner's browser check, see below |

### With `keycloak-db-restore.sh`

Done on 2026-10-28 in `rebuild` ([#1938](https://github.com/isejalabs/homelab/issues/1938)), a few minutes after the cluster had been booted from cold (image caches empty, Flux on `main`), restoring the same `qa` dump as the first drill (`keycloak-2026-10-26T011251Z.dump`, 282 KB) over a database that Keycloak had initialized (`scripts/keycloak-db-restore.sh -e rebuild --dump latest -y`):

| Step | Result |
| --- | --- |
| `--list` | 49 s the first time (cold images), 6 s warm |
| Phase 1: restore into the scratch database, compare | 96 s: the restore Job took 67 s including pod start and image pulls, no errors with `--exit-on-error`. Live: 101 tables, realm `master`, 1 user. Restored: 101 tables, realms `admin`, `iseja`, `master`, 3 users |
| Phase 2: writers stopped | 15 s (Flux suspended, operator and `StatefulSet` scaled to 0, no client connected) |
| Phase 3: swap | 1 s; the previous database stayed as `keycloak_before_20261028_215608` |
| Phase 4: `Keycloak` `Ready` again | 266 s: 89 s of it a cold pull of the Keycloak image on the freshly booted node, 41 s Keycloak's own start; expect about a minute with warm images, as in the first drill |
| Whole run | 378 s, of which Keycloak was down for about 4½ min (cold images) |
| State afterwards | Both `Kustomization`s resumed and `True`, operator back at 1 replica, `StatefulSet` 1/1, CronJob not suspended again, live database 101 tables with realms `admin`, `iseja`, `master` and 3 users |
| OIDC discovery | 200 for `master`, `iseja` and `admin` |
| Does Flux revert a manual scale-down of `keycloak-operator` when not suspended? | **Yes.** `kubectl scale deploy keycloak-operator --replicas=0`, then `flux reconcile kustomization keycloak-operator`: `spec.replicas` was back at 1 right after the reconcile. The suspend in phase 2 is needed |
| Login in `master` | Pending the owner's browser check: the `master` admin password comes from the `qa` dump, so it is the one in the `qa` item (see [A dump from another environment](#a-dump-from-another-environment)) |
| Not drilled | The [roll back](#roll-back) and a dump with a failing `pg_restore`; both are only covered by the offline checks of the script |

What the drill confirmed about the unverified parts of the script: `psql` as `postgres` over the local socket in the `postgres` container of the primary works, both renames succeed in one transaction once the `StatefulSet` is gone, the operator and `StatefulSet` names are right, and `kubectl wait keycloak/keycloak --for=condition=Ready` works.

### Encrypted dump, on a workstation

Done on 2026-11-01 for [#1939](https://github.com/isejalabs/homelab/issues/1939) with Docker, the real images of the CronJob (platform `linux/amd64`, user 26) and a local S3 mock (moto) instead of RustFS. The commands in the manifests were extracted and run unchanged:

| Step | Result |
| --- | --- |
| `fetch-age` | Downloaded `age` v1.3.2, `sha256sum -c` OK, `age --version` runs as a non-root user; the digest matches the one published for the release asset and one computed independently |
| `dump` with verification | `pg_dump` of a database with a `realm` table, then `pg_restore --list` OK; a truncated file and a text file both fail the check |
| `upload` with a test public key | `keycloak-<timestamp>.dump.age` uploaded (1517 bytes), the plaintext removed from the volume, heartbeat pinged. With `TODO-add-the-age-public-key` the job exits 1 before any upload and pings `/fail` |
| Retention | With 16 old dumps and an unrelated object in the bucket the three oldest dumps were pruned, the new dump and the unrelated object stayed |
| Restore Job built by `keycloak-db-restore.sh` | `fetch-age` + `download` + `restore` for a `.age` key, only `download` + `restore` for a plain one; the download step decrypts with the mounted key and `pg_restore --exit-on-error` restores both realms. A wrong key fails with `no identity matched any of the recipients` and leaves no dump |

**Not drilled**: a restore from an encrypted dump in a cluster (`qa` or `rebuild`), the temporary Secret path of the script against a live API server, the heartbeat against healthchecks.io, and the Checkmk check. The first two are the acceptance test of [#1939](https://github.com/isejalabs/homelab/issues/1939) and need the real age key and a cluster; they wait for the key and the owner's choice of environment.

### Observations of the manual drill

- **Tables and realms match the source**, but the restore cannot say anything about credentials Keycloak does not store. `sebi` and `sebi-adm` are federated: their password is checked against UCS, so Keycloak holds no local credential for them and "an existing credential" is only a UCS password until MFA exists ([#1827](https://github.com/isejalabs/homelab/issues/1827)). The only credential row in the dump is the master admin password.
- **WebAuthn is not exercised yet.** Nobody has enrolled one anywhere, so the part of the plan "login with an existing WebAuthn credential" stays open until #1827; repeat the login step of this drill then.
- **No sessions to test.** There are no applications yet, so the drill does not show what happens to existing app sessions; per the table under [Overview](#overview) they are lost anyway.
- **Hostname and TLS** come from the target's `Keycloak` resource (`rebuild-auth.rebuild.iseja.net`) and shared Gateway wildcard certificate (now Let's Encrypt production), not from the dump.

## Upgrading PostgreSQL

The server image is stated once, as `spec.imageName` (tag and digest) in [`cluster.yaml`](../../k8s/apps/identity/keycloak/base/cluster.yaml). Renovate tracks that line through a regex entry in [`renovate.json5`](../../.github/renovate.json5) and opens a PR for every new tag or digest; the package is excluded from automerge ([`automerge-disable.json5`](../../.github/renovate/automerge-disable.json5), label `updateStrategy:manual`), so an image change always waits for a human. The dump job follows by itself (see [How it works](#how-it-works)); the restore script derives its Job from the dump CronJob, so it uses that image too.

**Why it is pinned.** A cluster without `imageName` runs the default image of the installed CloudNativePG operator. Checked in the source of operator 1.30.1 (the version of the deployed chart 0.29.1): the defaulting (`setDefaults` in `api/v1/cluster_defaults.go`) fills an empty `imageName` with the operator's built-in default, `ghcr.io/cloudnative-pg/postgresql:18.6-system-trixie` in that release, and the controller rolls the instance pods whenever the image in the cluster status differs from the running pod's image. So the PostgreSQL version of an unpinned cluster is whatever the operator's default says whenever the cluster object is (re)defaulted, not a decision made in this repository, and a higher PostgreSQL major version in that default would start an offline in-place `pg_upgrade` (see below). Whether an operator upgrade alone moves an existing cluster depends on whether the stored value survives the next Flux apply, which is not settled by the source. The explicit pin makes the question moot: the PostgreSQL version changes only by a commit here. The explicit pin is the only thing that decides the version.

Observed in `dev` (2026-10-29, `dev` pointed at the branch that introduced the pin): the never-pinned cluster stored the operator default in `spec.imageName` (tag only); applying the pin changed the string to tag plus digest, and the operator replaced the instance pod once (Cluster back to `Cluster in healthy state`, Keycloak never restarted; the replacement took several minutes on that run, mostly pulling the 270 MB image on a node that did not have it yet, over a degraded internet link, so plan the window by the image pull of your link and not by this figure). Removing the line again made Flux drop the field and the operator re-default it, which replaced the pod a second time: a pin that is deleted from git un-pins the cluster. What an operator upgrade alone does to a cluster that was never pinned has not been observed.

**Minor and digest updates** (`18.6` to `18.7`, or a rebuilt `18.6` image): CloudNativePG replaces the instance pod, which on this single instance means a restart of the primary and a short Keycloak outage.

1. Trigger a backup right before ([Daily tasks](#daily-tasks)) and check that the dump landed in the bucket.
2. Test the update in a non-`prod` environment first: [`track-branch`](../../.agents/skills/track-branch/SKILL.md) the PR branch in `qa` (or `dev`), then wait until `kubectl get cluster keycloak-db -n keycloak` is `Cluster in healthy state` and the `Keycloak` resource is ready.
3. Run the dump job once by hand and restore that dump into a scratch database or into `rebuild` as described in [Restore](#restore). The dump job already uses the new client, so this is the check that new client, new server and restore still fit together.
4. Merge the PR. The other environments follow through Flux.

**Major updates** (`18` to `19`): CloudNativePG performs an offline in-place `pg_upgrade` as soon as the major version in `imageName` changes ([PostgreSQL upgrades](https://cloudnative-pg.io/docs/current/postgres_upgrades/)). The whole cluster is unavailable meanwhile, and the operator documents it as exceptional and risky.

1. Check that the Keycloak version in use supports the new PostgreSQL major version.
2. Trigger a backup right before and keep that dump. It was taken with the old client and restores into the old major version if the upgrade has to be rolled back (a dump of a newer major version may not restore into an older server).
3. Rehearse in `qa` (or `dev`) via `track-branch` as above: the upgrade job must complete, Keycloak must start, and a dump taken afterwards must restore.
4. Merge and watch the other environments. The dump job moves to the new client in the same commit, so the first dump after the upgrade is the new one.

## Why a dump and no WAL archiving

The first design archived WAL and took base backups with the Barman Cloud plugin. In `qa` that failed within hours: the backup credentials did not exist yet, archiving failed, and PostgreSQL does not recycle WAL it has not archived, so unarchived WAL filled the 1Gi volume and stopped the database. A separate WAL volume would only move the failure. A backup target that is down must never be able to take the live database down, so:

- The cluster has the annotation `cnpg.io/skipWalArchiving: enabled`, which sets `archive_mode = off`. WAL is recycled normally, whatever the state of the backup target. CloudNativePG documents this annotation as "use at your own risk" and it needs a restart of the instance; it was verified on `qa` (`archive_mode = off`, cluster ready).
- The database holds only a few MB (a fresh one is 13 MB), so a full dump is cheap and the 24 h recovery point is the daily schedule itself. There is no point-in-time recovery.
- The remaining WAL is kept small on purpose: `wal_keep_size 64MB` (CloudNativePG defaults to 512MB, half of this volume), `max_wal_size 256MB`, `min_wal_size 64MB`, `wal_compression on`, `wal_level replica`. The volume stays at 1Gi.

This differs from point 6 of [ADR 0016](../decisions/0016-identity-and-web-sso.md) (CloudNativePG base backups and WAL archiving to RustFS); the ADR is a historical record and is not rewritten; it carries a dated [amendment](../decisions/0016-identity-and-web-sso.md#status) that records the deployed backup method, instance counts and recovery point. The reasoning above is the current state.

## Known caveats

- **A lost age private key makes the dumps unreadable.** Keep two copies ([Encryption key](#encryption-key-age)); the realm configuration is code, so the worst case is the same as losing the dumps (see below).
- **The heartbeat covers `qa` only so far**, and the in-cluster restore from an encrypted dump has not been drilled yet (only the steps on a workstation, see [Restore drill](#restore-drill)).
- **The job's credential can delete every dump.** Retention runs in the upload container with the job's own credential (`aws s3 rm`), so the scoped `<env>-keycloak-db` user needs delete rights on its bucket, and a leaked key or a bug could remove all recovery points. Accepted by the owner on 2026-11-01: the job has to prune old dumps, and the worst case is bounded, because the realm configuration is code and the users re-enroll their MFA (see [Overview](#overview)). What limits the damage: the user reaches only its own bucket, and the prune loop only considers `keycloak-*` objects, always keeps the newest 14 and skips the object it just uploaded by name. Tested against a local S3 server (S3-compatible mock) with 16 old dumps and an unrelated object: the three oldest dumps were removed, the new dump and the unrelated object stayed. Not investigated: RustFS bucket lifecycle expiration and an upload-only policy, which would move the delete right away from the job; the policy lives in the shared Terraform module `rustfs-bucket-user`, so it would be a change there.
- **RustFS must be reachable at 02:00.** A failed run keeps the previous dumps; the next day's run tries again.
- **Kept databases fill the volume.** Every restore keeps the previous database as `keycloak_before_<timestamp>` on the 1Gi volume until you drop it; drop it once the restore is verified.
