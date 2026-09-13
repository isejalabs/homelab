# App storage

How an app configures the PVC it gets via `apps/storage/pvc` / `apps/storage/pvc-no-backup`
(see [k8s/components/apps/storage/README.md](../k8s/components/apps/storage/README.md) for which one to
pick). Scoped to the app-facing interface only -- not a Longhorn or Proxmox architecture doc.

All variables below are `${VAR:=default}`-style placeholders, resolved via Flux's `postBuild.substitute` in
the app's own `flux/ks.yaml` -- **not** the same mechanism as e.g. `DOMAIN_BASE`, which is a kustomize
`replacements` value resolved entirely at `kustomize build` time, no Flux involved. As of this writing, no
app actually overrides any of these yet (none currently consume `apps/storage/pvc`/`pvc-no-backup`), so
this is the intended, designed-for mechanism rather than an established one -- an app doing so for the
first time should add a `spec.postBuild.substitute: {STORAGE_CLASS: "longhorn-xfs", ...}` block to its own
`flux/ks.yaml` and confirm it actually resolves as expected. None of these are required -- every one has a
sensible default.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `STORAGE_CAPACITY` | `5Gi` | Size of the app's data PVC (also sizes the kopia mover's local dedup cache, which reuses this same value) |
| `STORAGE_ACCESSMODES` | `ReadWriteOnce` | The PVC's access mode |
| `STORAGE_CLASS` | `longhorn-standard` | The app's data PVC's storage class -- picks both filesystem and durability/performance tier, see the table below |
| `STORAGE_STAGING_CLASS` | `longhorn-scratch-ext4` | Only relevant for apps using `apps/storage/pvc` (active backup): the mover's disposable staging PVC's class. Must match `STORAGE_CLASS`'s filesystem -- see [Filesystem pairing](#filesystem-pairing) |
| `STORAGE_SNAPSHOTCLASS` | `longhorn-snapshot` | The `VolumeSnapshotClass` used to capture the source PVC |
| `PUID` / `PGID` | `1000` / `1000` | UID/GID the mover runs as -- match your app's own container UID/GID so file ownership survives a restore |
| `BACKUP_CACHE_STORAGECLASS` | `longhorn-standard` | Storage class for the kopia mover's local dedup cache volume -- a backup-mechanism detail, not a data-volume concern |

## Storage classes

The primary data-volume classes `STORAGE_CLASS` picks from (`longhorn-standard`/`longhorn-ext4`/
`longhorn-xfs`/`longhorn-fast`/`longhorn-ha`) -- their filesystem, replica count, and durability/performance
tradeoffs -- are documented once, as the canonical reference, in
[`docs/architecture/storage.md`](architecture/storage.md#storageclasses--one-driver-several-tradeoff-profiles);
not repeated here to avoid the two tables drifting out of sync. Filesystem alone doesn't fully determine
which one to pick -- `longhorn-xfs`/`longhorn-fast`/`longhorn-ha` are all xfs-backed but trade off
durability/performance differently, so picking one is still a deliberate choice, not something derived
automatically from "I want xfs."

Two more classes exist purely for the backup mover's disposable staging PVC (`STORAGE_STAGING_CLASS`) --
not in the architecture doc since they're a backup-mechanism detail, not an app data-volume concern. Both
are fast, single-replica, `strict-local`, differing only in filesystem:

| Class | Filesystem | Notes |
|---|---|---|
| `longhorn-scratch-ext4` | ext4 | Staging only -- never use for an app's actual data |
| `longhorn-scratch-xfs` | xfs | Staging only -- never use for an app's actual data |

## Filesystem pairing

`STORAGE_STAGING_CLASS` must match `STORAGE_CLASS`'s filesystem, or the mover fails at mount time ("wrong
fs type, bad superblock") -- a `VolumeSnapshot` restore is a raw block-level copy, not a reformat. Unlike
the primary class, staging only comes in two flavors (both single-replica, strict-local, disposable,
differing purely in `fsType`), so the rule is simple:

- `STORAGE_CLASS` is `longhorn-standard`/`longhorn-ext4` (ext4, the default) -> leave `STORAGE_STAGING_CLASS`
  at its default (`longhorn-scratch-ext4`).
- `STORAGE_CLASS` is `longhorn-xfs`/`longhorn-fast`/`longhorn-ha` (xfs) -> override `STORAGE_STAGING_CLASS`
  to `longhorn-scratch-xfs`.

This only matters for apps using `apps/storage/pvc` (active backup) -- an app on `pvc-no-backup` never runs
the mover, so an unmatched pairing there is inert.
