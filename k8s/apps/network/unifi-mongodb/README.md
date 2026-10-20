# unifi-mongodb

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

First seen in `prod` on 2026-10-20 (see `docs/kopiur-backup-restore.md` for the backup commands).
