---
status: planning
---

# Immich media storage on `fiona`

The media of [Immich](../../k8s/apps/media/immich/README.md) stay on the NAS `fiona` (TrueNAS 25.10) and reach the clusters over NFS. This page is the exact TrueNAS configuration for it: datasets, permissions, NFS exports, SMB shares for the Mac, snapshots, quotas and the borgbackup. The TrueNAS side is manual, so this is the one place that states it. The cluster side (static NFS `PersistentVolume`s and claims, no CSI driver) is in the [`immich` unit](../../k8s/apps/media/immich/README.md).

Why it is built this way is decided in [ADR 0018](../decisions/0018-media-source-of-truth.md) (Immich owns phone media, Lightroom Classic owns the existing library, which Immich reads read-only). The work is tracked in [#2144](https://github.com/isejalabs/homelab/issues/2144), part of [#413](https://github.com/isejalabs/homelab/issues/413). The status is `planning` until the owner has created the datasets and the [verification](#verify) has passed; then it becomes `current`.

## At a glance

| Row | Content |
| --- | --- |
| When to use | Creating, changing or checking the storage of Immich on `fiona`: a new environment, a replaced worker node (the export clients change), a quota or snapshot change. Not for the Immich database: it never goes on NFS, it stays on Longhorn ([#2145](https://github.com/isejalabs/homelab/issues/2145)) |
| Prerequisites | Admin access to the TrueNAS UI or shell on `fiona`; the [open owner inputs](#open-owner-inputs) answered; for the checks, `kubectl` with the context of the environment |
| Steps | [Datasets](#datasets), [permissions](#users-and-permissions), [NFS](#nfs), [SMB](#smb-for-the-mac), [snapshots](#snapshots), [quotas](#quotas-and-capacity), [borgbackup](#borgbackup), [test copies](#test-copies-for-non-prod) |
| Verify | [Verify](#verify): a pod mounts upload read-write and the library read-only, a deleted file comes back from a snapshot, a file comes back from the off-site borg repository |
| Rollback | Disable the NFS share (nothing mounts it any more) or destroy a non-prod dataset. A prod dataset is never destroyed by this procedure; the claims use `Retain`, so deleting Kubernetes objects leaves the data. No other rollback is documented |
| Last exercised | Not exercised yet. The values were derived from the repository, the Immich documentation and the [September 2026 TrueNAS audit](../audits/2026-09-observability-phase0-truenas-k8s-claude.md); anything marked *verify* has to be confirmed on `fiona` |

## Design in short

- Immich needs a POSIX filesystem with owners and permissions for its own data, and reads the Lightroom library and the rendition tree as two external libraries. All of it is on `fiona`; Longhorn disks of the workers are 30 GB at most.
- Four volumes per environment, one dataset each, so snapshot, quota, backup and export rules can differ:

  | Volume | Mode in Immich | Holds | Snapshots | Borgbackup |
  | --- | --- | --- | --- | --- |
  | `upload` | read-write | originals of phone uploads (`upload/`, `library/`, `profile/`), Immich's own database dumps (`backups/`) | yes | yes, `prod` only |
  | `cache` | read-write | thumbnails and encoded video (regenerable) | no | no |
  | `library` | **read-only** | the Lightroom Classic library, `YEAR/MONTH/DAY-Title` | the owner's existing rules | already part of the `fiona` backup |
  | `renditions` | **read-only** | JPEGs of edited RAWs, same folder layout, written by Lightroom Classic from the Mac | optional | optional (regenerable) |

- A read-only external library means Immich can neither delete nor rewrite an original: a delete in Immich comes back after the trash is emptied, and metadata edits are not possible (see [ADR 0018](../decisions/0018-media-source-of-truth.md#what-immich-does-with-a-library)). A writable mount would let Immich delete the original when the trash is emptied. So the library is read-only on three levels: the NFS share, the `ro` mount option and `nfs.readOnly` in the `PersistentVolume`.
- Non-prod environments only ever see **copies** of the library on test datasets of their own, never the live library, and no non-prod environment can reach `prod` data: every export lists only the worker nodes of one environment.
- The database never goes on NFS ([Immich requirements](https://docs.immich.app/install/requirements)).

## Datasets

All on the pool `natascha1`, in a new tree `natascha1/immich/` that is outside the datasets the current borgbackup covers (the audit found the `borgmatic` container mounting `/mnt/fiona1/data` and `/mnt/natascha1/data` only), so nothing is backed up by accident and what is backed up is listed explicitly under [borgbackup](#borgbackup). Create the parent datasets `natascha1/immich` and `natascha1/immich/<env>` without a share, then:

| Dataset | Environments | Mount path |
| --- | --- | --- |
| `natascha1/immich/<env>/upload` | `dev`, `qa`, `rebuild`, `prod` | `/mnt/natascha1/immich/<env>/upload` |
| `natascha1/immich/<env>/cache` | `dev`, `qa`, `rebuild`, `prod` | `/mnt/natascha1/immich/<env>/cache` |
| `natascha1/immich/<env>/library` | `dev`, `qa`, `rebuild`: **copies** | `/mnt/natascha1/immich/<env>/library` |
| `natascha1/immich/<env>/renditions` | `dev`, `qa`, `rebuild`: **copies** | `/mnt/natascha1/immich/<env>/renditions` |
| the existing Lightroom library dataset | `prod`: the live library, exported only | *owner input*, see [below](#open-owner-inputs) |
| a rendition dataset next to the library | `prod`: written from the Mac, exported read-only | *owner input* |

The prod rendition dataset is a **sibling** of the library dataset, not a child. A child dataset is a separate filesystem that an NFS export of its parent does not include, and nested shares of one tree are fragile. These paths are the ones in the `PersistentVolume`s ([`envs/<env>/kustomization.yaml`](../../k8s/apps/media/immich/envs)); change both together.

Dataset properties for all of them: `compression=lz4` (photos hardly compress, but it costs nothing), `recordsize=1M` (large files), `atime=off`, `sync=standard`, `copies=1`. ACL type: see [permissions](#users-and-permissions). Do not enable deduplication.

How Immich uses its volume, for the [Immich unit](../../k8s/apps/media/immich/README.md): the upload volume is `/data` (`IMMICH_MEDIA_LOCATION`, the default), the cache volume is mounted into it with `subPath: thumbs` and `subPath: encoded-video`, so Immich sees its usual folder layout while the regenerable parts live on a dataset of their own. Immich checks each of its folders for a hidden `.immich` file and reports a missing mount ([system integrity](https://docs.immich.app/administration/system-integrity)), so a volume that fails to mount is noticed, not silently replaced by an empty folder. The mount points of the two external libraries, and the import paths set in Immich for them, must stay the same for good: Immich stores the path of every asset, and a moved path is a deleted asset plus a new one (ADR 0018, rule 3).

## Users and permissions

One local account `immich` (user and group) on `fiona`, with **UID and GID `3100`** (proposed; any free ID works, but the Immich pod runs with the same numbers, see the [unit README](../../k8s/apps/media/immich/README.md#media-volumes)). It has no password and no shell.

- `upload` and `cache`: owner `immich:immich`, mode `0755`. The NFS share maps every client to `immich` (**Mapall user and group `immich`**), so it does not matter which user ID a container runs as, and files on `fiona` are always owned by `immich`.
- `library` and `renditions`: keep the owner they have; the mapped user `immich` only needs **read** access. Either the files are world-readable (the usual `0644`/`0755`), or the dataset gets a named-user ACL entry for `immich` with read and traverse, inherited. A *group* entry is not enough: TrueNAS 25.10 reports ignored group entries for Mapall users, see [this forum thread](https://forums.truenas.com/t/nfsv4-acl-group-based-permissions-not-honored-for-mapall-user-nfs-exports-on-scale/68097) (*verify*; the read check in [Verify](#verify) decides). The Mac keeps writing the renditions as its own user.
- ACL type: **POSIX** for `upload` and `cache`. A thread on 25.10 reports ownership problems on datasets with the `SMB/NFSv4` ACL type ([forum](https://forums.truenas.com/t/permissions-for-user-group-from-nfsv4-acls-are-ignored-when-mounting-shares-via-nfsv4/64362)). If the read-only SMB share of the `upload` dataset (see [SMB](#smb-for-the-mac)) does not work on a POSIX dataset, use the `SMB/NFSv4` type and a named-user entry for `immich`, and re-run the write check. The existing library datasets keep their ACL type.

## NFS

Services → NFS: enable **NFSv4** (NFSv3 is not needed). Talos mounts NFS from its kubelet image, so no system extension is required ([Talos storage guide](https://docs.siderolabs.com/kubernetes-guides/csi/storage): "The NFS client is part of the kubelet image maintained by the Talos team"); NFSv4 does not use the separate lock daemon that NFSv3 needs (*verify* on the first mount). The `PersistentVolume`s mount with `nfsvers=4.1,hard,noatime,nconnect=4`: `hard` so that a NAS outage stalls the pod instead of returning I/O errors to Immich in the middle of a write, `nconnect=4` for parallel connections (*verify* that the node kernel accepts it; drop it if the mount fails). The server name in the volumes is `fiona.home.iseja.net`, which the nodes have to resolve through their DNS (*verify*).

One share per dataset, Shares → NFS → Add. Settings that are the same for every share: **Security `SYS`**, **Maproot** empty, **Mapall user and group `immich`**, share enabled. The clients are listed as **Hosts**, never as a whole network: an export lists exactly the worker nodes of one environment (a pod only ever runs on a worker, and the kubelet of that node does the mount).

| Environment | Hosts (worker nodes) | `upload`, `cache` | `library`, `renditions` |
| --- | --- | --- | --- |
| `dev` | `10.7.8.134`, `10.7.8.135`, `10.7.8.136` | read-write | **Read-only** |
| `qa` | `10.7.8.124`, `10.7.8.125`, `10.7.8.126` | read-write | **Read-only** |
| `rebuild` | `10.7.8.174`, `10.7.8.175`, `10.7.8.176` | read-write | **Read-only** |
| `prod` | `10.7.8.184`, `10.7.8.185`, `10.7.8.186` | read-write | **Read-only** |

The addresses come from the Terragrunt units (`ip` of each `machine_type = "worker"` node in `terragrunt/<tier>/eu-central-1/<env>/vehagn-k8s/terragrunt.hcl`); the scheme is described in [`reference/environments.md`](../reference/environments.md#environment-id). **When a worker is added, replaced or renumbered, change the Hosts of that environment's four shares**, otherwise the pod on the new node cannot mount. List the current addresses:

```sh
awk '/^[[:space:]]*#/ {next} /machine_type/ {t=$3} /^[[:space:]]*ip[[:space:]]*=/ && t ~ /worker/ {print $3}' terragrunt/non-prod/eu-central-1/dev/vehagn-k8s/terragrunt.hcl
```

The live `prod` library is exported **read-only to the `prod` workers only**. The `qa`, `dev` and `rebuild` shares point at the test copies, so no non-prod cluster has any path to the live library or to `prod` upload data.

Network: TCP 2049 has to pass from the node VLAN to `fiona`. Kopiur already reaches `fiona` on port 9000 from the pods; NFS is a separate rule on the gateway if that VLAN is filtered (*verify*, the mount in the [test pod](#verify) shows it).

## SMB for the Mac

- **Upload dataset, read-only:** an SMB share `immich-upload` on `natascha1/immich/prod/upload` with **Read Only** enabled and access for the Mac's own account only, for the rare edit of a phone photo in Lightroom Classic (the edited copy goes back to Immich through the plugin, never into this share). The Mac reads as "other", so mode `0755`/`0644` is enough.
- **Rendition dataset, read-write for the Mac:** the Lightroom Classic publish service writes the renditions from the Mac. The protocol the Mac uses for the library today decides how this share is made, see [open owner inputs](#open-owner-inputs); SMB is assumed here. It is a share of the prod rendition dataset with write access for the Mac's account only. The NFS export of the same dataset stays read-only.
- The live library: no change. Whatever the Mac uses today stays; the NFS exports above do not touch it.

## Snapshots

Data Protection → Periodic Snapshot Tasks. Snapshots are the undo for an accidental or Immich-made delete of an original. A task per row, **not recursive** (every dataset has its own rule), naming schema as given so that two tasks on one dataset do not expire each other's snapshots:

| Dataset | Schedule | Keep | Naming schema |
| --- | --- | --- | --- |
| `prod` upload | hourly | 2 days | `auto-hourly-%Y%m%d-%H%M` |
| `prod` upload | daily | 30 days | `auto-daily-%Y%m%d-%H%M` |
| `prod` library | hourly / daily | 2 days / 30 days, unless the owner's existing tasks already cover it | same two schemas |
| `prod` rendition | daily (optional) | 7 days | `auto-daily-%Y%m%d-%H%M` |
| `qa` upload | daily | 7 days | `auto-daily-%Y%m%d-%H%M` |
| `cache`, `dev`, `rebuild`, test copies | none | | |

The `qa` task exists so the snapshot restore can be exercised outside `prod`. The 30 days match Immich's own trash retention (30 days by default): a delete in Immich is first undone by the trash, a delete outside Immich by the snapshots. Snapshots live in the same pool, so they protect against deletion and bad upgrades, not against a pool failure; that is what the borgbackup is for.

## Quotas and capacity

A quota keeps a runaway import from filling the pool (set `quota`, which counts snapshots too, not `refquota`). Proposed starting values; every one is a cap, not a reservation, and can be raised:

| Dataset | `dev` | `qa` | `rebuild` | `prod` |
| --- | --- | --- | --- | --- |
| `upload` | 20 GiB | 200 GiB | 20 GiB | from the inventory, see below |
| `cache` | 10 GiB | 60 GiB | 10 GiB | 10 to 20 % of library plus upload |
| `library` copy | 10 GiB | 400 GiB (one year, [#2309](https://github.com/isejalabs/homelab/issues/2309)) | 10 GiB | existing dataset, none |
| `renditions` copy | 5 GiB | 50 GiB | 5 GiB | from the number of edited RAWs |

For `prod`, size the upload quota as: expected phone uploads for the first year (4,000 to 10,000 assets a year across photos and videos, times the average size from the library inventory in [#2309](https://github.com/isejalabs/homelab/issues/2309)) plus 30 days of snapshot churn plus headroom, and revisit it after the [size test](https://github.com/isejalabs/homelab/issues/2147). The cache grows with library and uploads by 10 to 20 %.

> [!WARNING]
> The pool `natascha1` had **1.40 TiB free of 5.45 TiB** in the audit of 2026-09-30, and the live library is not counted in the new datasets (the external library is read in place, nothing is copied for `prod`). The `qa` copy of one year and the `prod` upload growth have to fit into what is free today: read the current free space (`zpool list natascha1`, `zfs list -o space natascha1`) before creating the datasets, and add up the quotas above and the `prod` values. If it does not fit, shrink the `qa` subset or add capacity first. This is an open owner input.

## borgbackup

The `prod` upload dataset holds originals (it is the master for phone media), not a transit copy, so it must be in the on-site and the off-site backup. The cache datasets, the renditions and all non-prod datasets are not backed up (regenerable, or copies). The live library is already part of the `fiona` backup.

The audit of 2026-09-30 found `borgmatic` as a container on `fiona` with `/mnt/fiona1/data` and `/mnt/natascha1/data` mounted, so `natascha1/immich` is not covered. To add `prod` upload:

1. Bind-mount `/mnt/natascha1/immich/prod/upload` **read-only** into the `borgmatic` container (and give it the same path inside).
2. Add the path to `source_directories` in the borgmatic configuration of the on-site **and** the off-site repository (*verify* in the actual configuration, which this repository does not hold).
3. Do not add `/mnt/natascha1/immich` as a whole: that would pull in the cache and the non-prod datasets.
4. Backup order matters for Immich: back up the database first, the files second, so that the worst case is a file the database does not know, not the reverse ([Immich backup and restore](https://docs.immich.app/administration/backup-and-restore)). Immich's own database dumps are in `upload/backups/`, so they are included; the CloudNativePG dump to RustFS ([#2145](https://github.com/isejalabs/homelab/issues/2145)) should finish before the borg run starts (*verify* the schedules once both exist).

## Test copies for non-prod

`dev` gets at most 10 photos and videos, `qa` one year (about 5,000 assets, with edited and unedited `.NEF` and `.ARW`, HEIC, Live Photos and videos; the choice of the year follows the inventory of [#2309](https://github.com/isejalabs/homelab/issues/2309)). Copy, never move, with the live library as the **source only**, on `fiona` (`<live library>` and `<live renditions>` are the datasets from the [owner input](#open-owner-inputs)):

```sh
# qa: one year of the library and of its renditions, with sidecars; the copy is owned by the Immich account
rsync -a --chown=immich:immich "<live library>/2024/" /mnt/natascha1/immich/qa/library/2024/
rsync -a --chown=immich:immich "<live renditions>/2024/" /mnt/natascha1/immich/qa/renditions/2024/

# dev: pick the items by hand (a RAW with its .xmp sidecar, a HEIC, a video); -R keeps the folders below the "/./" anchor
rsync -aR --chown=immich:immich "<live library>/./2024/05/12-Title/IMG_0001.NEF" "<live library>/./2024/05/12-Title/IMG_0001.xmp" /mnt/natascha1/immich/dev/library/
```

The copies keep the folder layout (`YEAR/MONTH/DAY-Title`) and are then exported read-only like the live library. The Lightroom catalog copy for the proof of concept stays on the Mac; it is not part of any export.

## Verify

These are the acceptance criteria of [#2144](https://github.com/isejalabs/homelab/issues/2144). Run the first on `dev` and on `qa`, the second on any environment with snapshots (`qa`), the third once for `prod`.

1. **Mounts, read-write and read-only.** With the `immich` unit applied in the environment (merged, or [`track-branch`](../../.agents/skills/track-branch/SKILL.md) on `dev`), apply the test pod and read its result:

   ```sh
   kubectl --context admin@dev-homelab apply -f k8s/test/storage/test-nfs-immich-media.yaml
   kubectl --context admin@dev-homelab -n immich logs test-nfs-immich-media
   kubectl --context admin@dev-homelab delete -f k8s/test/storage/test-nfs-immich-media.yaml
   ```

   Expected: `OK` for `upload` and `cache` writable, and for `library` and `renditions` both `read-only` and `readable`, and the `mount` lines show `nfs4` with `ro` on the two read-only ones. A `FAIL ... not readable` on a read-only volume means the mapped user `immich` cannot read the files: see [permissions](#users-and-permissions). A pod stuck in `ContainerCreating` is a mount problem: `kubectl describe pod` shows the NFS error (export hosts, firewall, name resolution).
2. **Restore a deleted file from a snapshot.** On `fiona`, with a `qa` snapshot task running (or a manual snapshot):

   ```sh
   echo canary > /mnt/natascha1/immich/qa/upload/snapshot-test.txt
   zfs snapshot natascha1/immich/qa/upload@manual-test
   rm /mnt/natascha1/immich/qa/upload/snapshot-test.txt
   cp /mnt/natascha1/immich/qa/upload/.zfs/snapshot/manual-test/snapshot-test.txt /mnt/natascha1/immich/qa/upload/
   zfs destroy natascha1/immich/qa/upload@manual-test
   rm /mnt/natascha1/immich/qa/upload/snapshot-test.txt
   ```

   Expected: the `cp` finds the file in the snapshot and the content is `canary`.
3. **Restore a file from the off-site borg repository.** Put a canary file in the `prod` upload dataset next to Immich's folders (`restore-test/<date>.txt`; Immich only uses its own folders), wait for the backup run, then extract it from the off-site repository with the installed borgmatic (`borgmatic extract --help` for the exact flags of that version) into a scratch directory, never over the live dataset:

   ```sh
   borgmatic list --repository <off-site repository> --archive latest --find restore-test
   borgmatic extract --repository <off-site repository> --archive latest --path <path of the file in the archive> --destination /tmp/borg-restore
   ```

   Expected: the extracted file equals the original. After the first real uploads, repeat it once with a real asset.

## Monitoring

`fiona` already has the Checkmk agent. Run a service discovery on the host after the datasets exist and check that the new datasets show up as filesystem services, set the usage thresholds on `prod` upload with the quota in mind, and add the quota fill level of the non-prod datasets as a warning only (*verify* what the existing ZFS dataset check on `fiona` reports, see the [RustFS capacity audit](../audits/2026-10-rustfs-capacity.md)). The RustFS quota monitoring in [`terragrunt/README.md`](../../terragrunt/README.md) is unrelated to these datasets.

## Open owner inputs

These are not guessed in the repository; the manifests carry a placeholder where they are needed:

1. **Which dataset holds the live Lightroom library, and which the future rendition tree.** The audit lists Syncthing folders under `/mnt/natascha1/data/media/` (`Lightroom-Data`, `media-Pictures-Sync`, `media-Pictures-orig`, `media-Videos-orig`) but the repository does not say which of them is the `YEAR/MONTH/DAY-Title` library. The `prod` overlay carries `LIBRARY_DATASET` and `RENDITIONS_DATASET` as placeholders for it.
2. **Which protocols the Mac uses** for the library today (SMB or NFS) and so which one the rendition share and the read-only upload share should use.
3. **Pool capacity:** current free space of `natascha1` and whether the `qa` copy of one year fits (see the warning under [quotas](#quotas-and-capacity)).
4. **UID/GID `3100`** for the `immich` account: confirm it is free on `fiona`, or name another.
5. **`borgmatic` configuration** of the on-site and the off-site repository, to add the `prod` upload path.

## Related

- [ADR 0018](../decisions/0018-media-source-of-truth.md): the media model this storage implements
- [`k8s/apps/media/immich`](../../k8s/apps/media/immich/README.md): the Kubernetes side, static NFS volumes
- [`k8s/test/storage/test-nfs-immich-media.yaml`](../../k8s/test/storage/test-nfs-immich-media.yaml): the mount test
- [CSI alternatives (#455)](https://github.com/isejalabs/homelab/issues/455): why a static volume is enough here
