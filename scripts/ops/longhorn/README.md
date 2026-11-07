# Longhorn volume snapshots

Wrapped by `just backup::longhorn-snapshot::<list|create|restore>` — see [`mod.just`](mod.just) and [`docs/backup/longhorn-snapshots.md`](../../../docs/backup/longhorn-snapshots.md). These cover Longhorn's own local snapshots (the `hourly-snapshot`/`daily-backup` `RecurringJob`s plus manual ones), e.g. in environments with no kopiur backup. Hourly snapshots are only retained for ~24 hours, so pick one by its `CREATED` timestamp rather than by day. Each script documents its purpose and usage in a header comment; this README is an index, not a duplicate of that.

| Script | Purpose |
| --- | --- |
| [`mod.just`](mod.just) | the `just` recipes `list`, `create` and `restore` |
| [`snapshot-list.sh`](snapshot-list.sh) | lists Longhorn `Snapshot` CRs per app (PVC), newest first, for one app or every app in scope |
| [`snapshot-create.sh`](snapshot-create.sh) | triggers a manual snapshot, for one app or every Longhorn volume in scope (`--all`); manual snapshots are never auto-pruned |
| [`snapshot-restore.sh`](snapshot-restore.sh) | rolls an app's PVC back to a snapshot: automates the Flux suspend/scale-down/scale-up and pauses for the manual revert in the Longhorn UI; takes a `pre-restore-*` safety snapshot first |

All three source [`lib/common.sh`](../../lib/common.sh) and [`lib/longhorn.sh`](../../lib/longhorn.sh) (PVC → Longhorn volume lookup).
