---
status: current
---

# App storage

How an app configures the PVC it gets via `apps/storage/pvc` / `apps/storage/pvc-no-backup` (see [k8s/components/apps/storage/README.md](../k8s/components/apps/storage/README.md) for which one to pick). Scoped to the app-facing interface only -- not a Longhorn or Proxmox architecture doc.

All variables below are `${VAR:=default}`-style placeholders, resolved via Flux's `postBuild.substitute` in the app's own `flux/ks.yaml` -- **not** the same mechanism as e.g. `DOMAIN_BASE`, which is a kustomize `replacements` value resolved entirely at `kustomize build` time, no Flux involved. As of this writing, no app actually overrides any of these yet (none currently consume `apps/storage/pvc`/`pvc-no-backup`), so this is the intended, designed-for mechanism rather than an established one -- an app doing so for the first time should add a `spec.postBuild.substitute: {STORAGE_CLASS: "longhorn-xfs", ...}` block to its own `flux/ks.yaml` and confirm it actually resolves as expected. None of these are required -- every one has a sensible default.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `STORAGE_CAPACITY` | `5Gi` | Size of the app's data PVC (also sizes the kopia mover's local dedup cache, which reuses this same value) |
| `STORAGE_ACCESSMODES` | `ReadWriteOnce` | The PVC's access mode |
| `STORAGE_CLASS` | `longhorn-standard` | The app's data PVC's storage class -- picks both filesystem and durability/performance tier, see the table below |
| `STORAGE_STAGING_CLASS` | `longhorn-scratch-ext4` | Only relevant for apps using `apps/storage/pvc` (active backup): the mover's disposable staging PVC's class. Must match `STORAGE_CLASS`'s filesystem -- see [Filesystem pairing](#filesystem-pairing) |
| `STORAGE_SNAPSHOTCLASS` | `longhorn-snapshot` | The `VolumeSnapshotClass` used to capture the source PVC |
| `PUID` / `PGID` | `1000` / `1000` | UID/GID the mover runs as -- match your app's own container UID/GID so file ownership survives a restore |
| `BACKUP_CACHE_STORAGECLASS` | `longhorn-cache` | Storage class for the kopia mover's local dedup cache volume -- a backup-mechanism detail, not a data-volume concern. Must be a `reclaimPolicy: Delete` class, so a recreated cache PVC does not leave an orphaned volume behind |

## Storage classes

The primary data-volume classes `STORAGE_CLASS` picks from (`longhorn-standard`/`longhorn-ext4`/ `longhorn-xfs`/`longhorn-fast`/`longhorn-ha`) -- their filesystem, replica count, and durability/performance tradeoffs -- are documented once, as the canonical reference, in [`docs/architecture/storage.md`](architecture/storage.md#storageclasses--one-driver-several-tradeoff-profiles); not repeated here to avoid the two tables drifting out of sync. Filesystem alone doesn't fully determine which one to pick -- `longhorn-xfs` is the only xfs-backed class (every other class is ext4); `longhorn-fast`/`longhorn-ha` trade off durability/performance differently, so picking one is still a deliberate choice.

Three more classes exist purely for the backup mover (kopiur) -- not in the architecture doc since they're a backup-mechanism detail, not an app data-volume concern. The mover uses two different temporary volumes per app, with different jobs; see [How it works](kopiur-backup-restore.md#ongoing-protection-appsstoragepvc-only) in the kopiur doc for the full backup sequence. All three are `reclaimPolicy: Delete`: nothing on them is worth keeping, so deleting the PVC also removes the volume.

| Class | Used for (variable) | Filesystem | Replicas | Lifetime |
|---|---|---|---|---|
| `longhorn-scratch-ext4` / `longhorn-scratch-xfs` | **Staging** PVC (`STORAGE_STAGING_CLASS`) | must match the source (`STORAGE_CLASS`) | 1, `strict-local` | one backup run: created from the `VolumeSnapshot`, read by the mover, deleted afterwards |
| `longhorn-cache` | **Cache** PVC (`BACKUP_CACHE_STORAGECLASS`) | ext4, independent of `STORAGE_CLASS` | 2, not `strict-local` | persistent: kept between runs, only rebuilt if deleted |

- **Staging (`longhorn-scratch-*`)** holds a full, temporary *copy of the app's data*: kopiur restores the `VolumeSnapshot` of the source PVC into it (a raw block copy, hence the matching-filesystem rule below) and the mover reads from there, so the app's live volume is never read directly. It only exists while a backup runs, so speed matters more than durability: one replica, on the node running the mover.
- **Cache (`longhorn-cache`)** holds kopia's local *metadata and content cache*, not app data. It is what lets the next run quickly recognise what the repository already contains, instead of listing it again from `fiona`. It is reused by every run, so it is persistent and keeps two replicas so a single node outage does not stall the backup; if lost, it is only rebuilt from the repository (slower next run, no data loss). Because it contains no copy of the source's blocks, its filesystem has nothing to match: an app on an xfs `STORAGE_CLASS` such as `longhorn-xfs` (e.g. unifi-mongodb) uses the same ext4 cache class, so there is no xfs variant.

## Filesystem pairing

`STORAGE_STAGING_CLASS` must match `STORAGE_CLASS`'s filesystem, or the mover fails at mount time ("wrong fs type, bad superblock") -- a `VolumeSnapshot` restore is a raw block-level copy, not a reformat. Unlike the primary class, staging only comes in two flavors (both single-replica, strict-local, disposable, differing purely in `fsType`), so the rule is simple:

- `STORAGE_CLASS` is `longhorn-standard`/`longhorn-ext4`/`longhorn-fast`/`longhorn-ha` (ext4, the default) -> leave `STORAGE_STAGING_CLASS` at its default (`longhorn-scratch-ext4`).
- `STORAGE_CLASS` is `longhorn-xfs` (the only xfs-backed class) -> override `STORAGE_STAGING_CLASS` to `longhorn-scratch-xfs`.

This only matters for apps using `apps/storage/pvc` (active backup) -- an app on `pvc-no-backup` never runs the mover, so an unmatched pairing there is inert.
