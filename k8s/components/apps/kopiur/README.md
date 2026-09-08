## Purpose

Two shared kustomize `Component`s used to wire an app's PVC into [kopiur](https://github.com/home-operations/kopiur) backup.

- **`backup/`** — PVC + `SnapshotPolicy` + `SnapshotSchedule` + `Restore`. Everything needed for an app's data volume to be automatically backed up hourly to the `fiona` `ClusterRepository`, and to be restorable via the CSI populator mechanism when its PVC is (re)created. Depends on `secret/` (included automatically — apps consuming `backup/` don't need to reference `secret/` separately).
- **`secret/`** — a per-namespace `kopiur-repository-secret` `ExternalSecret`. The mover Job that talks to `fiona` needs these credentials in its *own* namespace (`envFrom` is namespace-local), separate from the copy `kopiur-repository` keeps in `kopiur-system`.

An app opts in by adding `backup/` to its `base/kustomization.yaml` `components:` list — per-env credentials (`kopiur-secret`'s `dataFrom.extract.key`) are rewritten automatically by the `kopiur-secret-env` transformer, no per-app patching needed. The one override apps typically still need is `KOPIUR_STAGING_STORAGECLASS` (via `postBuild.substitute` in the app's `flux/ks.yaml`), for apps whose data volume is xfs-backed (see the caveats in the doc below).

For the full mechanism (how automatic restore/create-on-first-deploy works) and day-to-day operational tasks (list backups, manual backup, restore, prune), see [docs/kopiur-backup-restore.md](../../../../docs/kopiur-backup-restore.md).
