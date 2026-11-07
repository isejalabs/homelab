# unifi-mongodb

[MongoDB](https://www.mongodb.com/) as the database of [`unifi-controller`](../unifi-controller/README.md). A single instance with its own PVC.

## At a glance

| | |
| --- | --- |
| Namespace | `unifi` (this unit owns the namespace manifest; `unifi-controller` shares it) |
| Runs in | `head`, `prod`, `qa`, `rebuild` (Flux set `optional`) |
| Installed via | Raw manifests (Deployment `mongodb`, Service `mongodb`) and the `apps/storage/pvc` component (2Gi on `longhorn-xfs`, backed up by kopiur) |
| Flux Kustomization | `unifi-mongodb`, depends on `cilium`, `proxmox-csi`, `sealed-secrets` |

## Purpose

The UniFi controller needs a MongoDB; this is a plain one-pod deployment for it, with credentials from the SealedSecret `db-secret-sealed`.

## Where it is used

- **Used by**: [`unifi-controller`](../unifi-controller/README.md) only.
- **Depends on**: its PVC (`longhorn-xfs`, user and group `999`), `sealed-secrets` for the credentials.

## Access

Not exposed. In-cluster only, on the Service `mongodb.unifi:27017`.

## Updates

- **Image**: `docker.io/mongo` with tag and digest in [`base/deployment.yaml`](base/deployment.yaml).
- **Pinned to 8.0**: minor updates beyond `8.0` are blocked because the UniFi controller requires it (and to avoid no-op minor bumps). `head` and `poc` track the newest version as an early warning: [`pin-versions.json5`](../../../../.github/renovate/pin-versions.json5), [Non-standard update strategies](../../../../docs/operations/update-handling.md#non-standard-update-strategies).

## Operations

| Task | Doc |
| --- | --- |
| Back up and restore | [`kopiur-backup-restore.md`](../../../../docs/backup/kopiur-backup-restore.md) |
| PVC or volume problems | [`troubleshooting-storage.md`](../../../../docs/troubleshooting/troubleshooting-storage.md) |

## Cheat sheet

```sh
flux get ks unifi-mongodb --context admin@<env>-homelab
kubectl get pods,svc,pvc -n unifi --context admin@<env>-homelab
kubectl logs -n unifi deploy/mongodb -f --context admin@<env>-homelab

# backup now (see the quirk below before opening a shell in the pod)
just backup::kopiur::create unifi-mongodb -e <env> -n unifi
```

## Upstream

- Homepage and documentation: <https://www.mongodb.com/docs/manual/>
- Image: <https://hub.docker.com/_/mongo>

## Do not run `mongosh` as root

The kopiur backup of this app runs as uid 999 with group 65532 (`fsGroup`). `mongosh` run as **root** inside the pod (for example a plain `kubectl exec ... -- mongosh`) writes its logs as root with mode `0600` under `/data/db/.mongodb/mongosh/`. The backup user cannot read them, and the whole snapshot then fails:

```text
snapshot create failed (class PermissionDenied): ... .mongodb/mongosh/<id>_log: permission denied
```

A failed snapshot is silent until the scheduled run, so the app can go without a good backup for days.

Run `mongosh` as the `mongodb` user instead:

```sh
k exec -n unifi deploy/mongodb -- su mongodb -s /bin/sh -c 'mongosh ...'
```

If it already happened, make the leftover root-owned files group-readable (one-off, no data is changed) and take a manual backup to confirm:

```sh
k exec -n unifi deploy/mongodb -- sh -c 'find /data/db -user root ! -perm -g=r -type f -exec chmod g+r {} +'
just backup::kopiur::create unifi-mongodb -e <env> -n unifi
```

First seen in `prod` on 2026-10-20 (see `docs/backup/kopiur-backup-restore.md` for the backup commands).
