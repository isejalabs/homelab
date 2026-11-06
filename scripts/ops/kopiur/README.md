# kopiur backup/restore

Wrapped by `just backup::kopiur::<list|create|restore|bypass-restore|migrate|convert-storage-class>` — see [`mod.just`](mod.just) and [`docs/backup/kopiur-backup-restore.md`](../../../docs/backup/kopiur-backup-restore.md) for the day-to-day operational guide. Each script documents its purpose and usage in a header comment; this README is an index, not a duplicate of that.

| Script | Purpose |
| --- | --- |
| [`mod.just`](mod.just) | the `just` recipes `list`, `create`, `restore`, `bypass-restore`, `migrate` and `convert-storage-class` |
| [`list.sh`](list.sh) | lists kopiur `Snapshot` CRs, for one app or every app in scope |
| [`create.sh`](create.sh) | triggers a manual `Snapshot`, for one app or every app in scope (`--all`) |
| [`restore.sh`](restore.sh) | restores an app's PVC from its latest snapshot (deletes and repopulates the PVC) |
| [`bypass-restore.sh`](bypass-restore.sh) | gives an app a blank PVC without deleting its kopiur backups, for importing data by other means (e.g. from another environment); interactive |
| [`migrate-pvc.sh`](migrate-pvc.sh) | copies an app's data from an old PVC onto its new kopiur-managed PVC ahead of a `claimName`/`existingClaim` cut-over; leaves the owning Flux object suspended and the app scaled to 0 |
| [`convert-storageclass.sh`](convert-storageclass.sh) | converts a kopiur-managed PVC onto a different StorageClass in place (copies the data to a new PVC and rebinds it under the original name), e.g. ext4 to xfs |

All six source [`lib/common.sh`](../../lib/common.sh) for gum-backed logging, environment validation, kubecontext construction, and unrecognized-flag handling shared across them.
