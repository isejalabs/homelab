## Purpose

Shared kustomize `Component`s for provisioning an app's PVC. An app needing storage includes exactly one
of these in its `base/kustomization.yaml` — requiring a PVC gets it backed up automatically, by default.

- **`pvc/`** (the default) — `PVC` + `Restore` + `SnapshotPolicy` + `SnapshotSchedule`. Everything needed
  for an app's data volume to be automatically backed up daily to the `fiona` `ClusterRepository`, and to
  be restorable via the CSI populator mechanism when its PVC is (re)created.
- **`pvc-no-backup/`** — the explicit exception: `PVC` + `Restore` + `SnapshotPolicy`, no `SnapshotSchedule`.
  For storage that genuinely doesn't need protecting (e.g. ephemeral/regenerable data), but still needs
  real, reschedulable storage rather than node-local disk. `pvc/` is built on top of this (adds the
  schedule) rather than the other way round — `pvc-no-backup/`'s files are the canonical copy.

Both depend on [`apps/kopiur/secret`](../kopiur/secret) automatically — no separate reference needed. In
environments where kopiur backup isn't actively scheduled (`dbg`/`head`/`poc`/`src` as of this writing),
any `SnapshotSchedule` an app creates via `pvc/` is force-suspended by the
[`suspend-kopiur-schedule`](../../transformers/suspend-kopiur-schedule) transformer, registered per-env —
this overrides whichever component an app picked, as a guardrail.

Per-env credentials (`kopiur-secret`'s `dataFrom.extract.key`) are rewritten automatically by the
`kopiur-secret-env` transformer — no per-app patching needed. See
[docs/app-storage.md](../../../../docs/app-storage.md) for the full `STORAGE_*`/`PUID`/`PGID` variable
reference and the storage-class/filesystem pairing rules, and
[docs/kopiur-backup-restore.md](../../../../docs/kopiur-backup-restore.md) for how the backup/restore
mechanism itself works.
