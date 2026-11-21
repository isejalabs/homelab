---
status: planning
---

# Immich media storage on `fiona`

The media of [Immich](../../k8s/apps/media/immich/README.md) stay on the NAS `fiona` (TrueNAS 25.10) and reach the clusters over NFS. This page is the exact TrueNAS configuration for it: datasets, permissions, NFS exports, the access of the Mac, snapshots and the borgbackup. The TrueNAS side is manual, so this is the one place that states it. The cluster side (static NFS `PersistentVolume`s and claims, no CSI driver) is in the [`immich` unit](../../k8s/apps/media/immich/README.md).

Why it is built this way is decided in [ADR 0018](../decisions/0018-media-source-of-truth.md) (Immich owns phone media, Lightroom Classic owns the existing library, which Immich reads read-only). The work is tracked in [#2144](https://github.com/isejalabs/homelab/issues/2144), part of [#413](https://github.com/isejalabs/homelab/issues/413). The status is `planning` until the owner has created the datasets and the [verification](#verify) has passed; then it becomes `current`.

## At a glance

| Row | Content |
| --- | --- |
| When to use | Creating, changing or checking the storage of Immich on `fiona`: a new environment, a replaced worker node (the export clients change), a snapshot change. Not for the Immich database: it never goes on NFS, it stays on Longhorn ([#2145](https://github.com/isejalabs/homelab/issues/2145)) |
| Prerequisites | Admin access to the TrueNAS UI or shell on `fiona`; the [open owner inputs](#open-owner-inputs) answered; for the checks, `kubectl` with the context of the environment |
| Steps | [Datasets](#datasets), [permissions](#users-and-permissions), [NFS](#nfs), [Mac access](#access-from-the-mac), [snapshots](#snapshots), [capacity](#capacity), [borgbackup](#borgbackup), [copies of the library](#copies-of-the-library-for-non-prod) |
| Verify | [Verify](#verify): a pod mounts upload and cache read-write and library and export read-only, a deleted file comes back from a snapshot, a file comes back from the off-site borg repository |
| Rollback | Disable the NFS share (nothing mounts it any more) or destroy a non-prod dataset. A prod dataset is never destroyed by this procedure; the claims use `Retain`, so deleting Kubernetes objects leaves the data. No other rollback is documented |
| State | 2026-11-21: datasets, clones and the NFS shares exist for `dev`, `qa` and `rebuild`, the `prod` datasets and shares exist too, the ACL entry for `dev` and `qa`, and Verify 1 passed on `dev` and `qa` (NFSv4.1, `nconnect=4`, `sec=sys`). The `qa` snapshot task exists and the snapshot restore (Verify 2) is being checked, and the on-site borg restore of the `prod` canary passed on 2026-11-21 (the off-site one waits for its host). Not done yet: the borg restore (Verify 3), which needs the borgmatic container restarted first, and the ACL entry on the live library |
| Last exercised | Not exercised yet. The values were derived from the repository, the Immich documentation and the [September 2026 TrueNAS audit](../audits/2026-09-observability-phase0-truenas-k8s-claude.md); anything marked *verify* has to be confirmed on `fiona` |

## Design in short

- Immich needs a POSIX filesystem with owners and permissions for its own data, and reads the Lightroom library and the export tree (JPEG renditions of edited RAWs) as two external libraries. All of it is on `fiona`; Longhorn disks of the workers are 30 GB at most.
- Four volumes per environment, so snapshot, backup and export rules can differ:

  | Volume | Mode in Immich | Holds | Snapshots | Borgbackup |
  | --- | --- | --- | --- | --- |
  | `upload` | read-write | originals of phone uploads (`upload/`, `library/`, `profile/`), Immich's own database dumps (`backups/`) | yes | yes, `prod` only |
  | `cache` | read-write | thumbnails and encoded video (regenerable) | no | no |
  | `library` | **read-only** | the Lightroom Classic library (the folder `Pictures/orig`), `YEAR/MONTH/DAY-Title` | the owner's existing rules | already part of the `fiona` backup |
  | `export` | **read-only** | JPEG renditions of edited RAWs, same folder layout, written by Lightroom Classic on the Mac and synced to the NAS by Syncthing | the owner's existing rules | no: the existing configuration excludes `Pictures/export` (regenerable) |

- A read-only external library means Immich can neither delete nor rewrite an original: a delete in Immich comes back after the trash is emptied, and metadata edits are not possible (see [ADR 0018](../decisions/0018-media-source-of-truth.md#what-immich-does-with-a-library)). A writable mount would let Immich delete the original when the trash is emptied. So the library is read-only on three levels: the NFS share, the `ro` mount option and `nfs.readOnly` in the `PersistentVolume`.
- Non-prod environments only ever see **copies** of the library (ZFS clones, see [below](#copies-of-the-library-for-non-prod)), never the live library, and no non-prod environment can reach `prod` data: every export lists only the worker nodes of one environment.
- Two pools carry the data: the important data (`prod` upload, the live library and its export) is on `natascha1`, everything of less value (all non-prod upload and cache, and the `prod` cache) on `fiona2`. The copies of the library have to be on `natascha1`, because a ZFS clone lives in the pool of its origin.
- Read-only is enforced by the NFS share options (and, as a second and third level, the `ro` mount option and `nfs.readOnly`), **not** by filesystem permissions: the group that Immich's account belongs to has write access on the whole `natascha1/data/media` dataset, so the library and export folders are writable on the filesystem level. A path to these folders that is not the read-only share would be a path with write access.
- The database never goes on NFS ([Immich requirements](https://docs.immich.app/install/requirements)).

## Datasets

The NFS export of a dataset or folder is always its mount path `/mnt/<dataset>`: `natascha1/data/srv/immich` is shared as `/mnt/natascha1/data/srv/immich` (here the folder `upload` of it, `/mnt/natascha1/data/srv/immich/upload`). The `PersistentVolume`s carry exactly these paths ([`envs/<env>/kustomization.yaml`](../../k8s/apps/media/immich/envs)); change both together.

| Volume | Dataset | Environments |
| --- | --- | --- |
| `upload` | `natascha1/data/srv/immich/upload` (`prod`), `fiona2/gamma/srv/immich/<env>/upload` (non-prod); in both cases the folder `upload` of the dataset `natascha1/data/srv/immich` or `fiona2/gamma/srv/immich/<env>` | `dev`, `qa`, `rebuild`, `prod` |
| `cache` | `fiona2/gamma/srv/immich/<env>/cache` (directory of the same dataset) | `dev`, `qa`, `rebuild`, `prod` |
| `library` (`pictures`) | `natascha1/gamma/srv/immich-copy/<env>/Pictures/orig` | `dev`, `qa`, `rebuild`: **copies** |
| non-prod `export` (renditions) | `natascha1/gamma/srv/immich-copy/<env>/Pictures/export` | `dev`, `qa`, `rebuild`: **copies** |
| `prod` `library` | the existing Lightroom library, the folder `natascha1/data/media/Pictures/orig` | `prod`: the live library, exported only |
| `prod` `export` | the folder `natascha1/data/media/Pictures/export` | `prod`: synced from the Mac by Syncthing, exported read-only |
| videos-only library | `natascha1/data/media/Videos/` | postponed, not part of the proof of concept yet |
| renditions of the videos-only library | | postponed, not part of the proof of concept yet |

Notes on the table:

- **`upload` and `cache`** are folders of one dataset per environment, `fiona2/gamma/srv/immich/<env>`, not datasets of their own, so snapshots apply to the two together (the cache is regenerable and is snapshotted along, which only costs space). `prod` has the same shape on the other pool: the dataset `natascha1/data/srv/immich` with the folder `upload`, which leaves room for another folder next to it later. It is a child of `natascha1/data` on purpose: it is then inside the tree that the existing snapshots and the borgbackup already cover, see [snapshots](#snapshots) and [borgbackup](#borgbackup).
- **`Pictures/orig` and `Pictures/export` of the copies** are *folders* of a cloned dataset (the clone mirrors `natascha1/data/media`: `Music`, `Pictures`, `Videos`, `clipart`, `fonts`), see [Copies of the library](#copies-of-the-library-for-non-prod). On the live side the `prod` library and the `prod` export are folders of the dataset `natascha1/data/media` as well, not datasets of their own, and the NFS shares are made on these folders.
- The copies sit in their own hierarchy, `immich-copy`, apart from `immich`, so that a clone can be thrown away and made again without touching the `upload` and `cache` data of the same environment.

Created for `dev` and `qa` by the owner on 2026-11-18, the same commands apply to `rebuild` and `prod` (for `prod` only the `cache` directory, the `upload` path is the one in the table):

```sh
zfs create fiona2/gamma/srv/immich/dev
zfs create fiona2/gamma/srv/immich/qa
mkdir -p /mnt/fiona2/gamma/srv/immich/dev/upload /mnt/fiona2/gamma/srv/immich/dev/cache
mkdir -p /mnt/fiona2/gamma/srv/immich/qa/upload /mnt/fiona2/gamma/srv/immich/qa/cache
chown -R immich:fs.media-rw /mnt/fiona2/gamma/srv/immich/
```

Dataset properties for the new datasets (`fiona2/gamma/srv/immich/<env>`): `compression=lz4` (photos hardly compress, but it costs nothing), `recordsize=1M` (large files), `atime=off`, `sync=standard`, `copies=1`. ACL type: see [permissions](#users-and-permissions). Do not enable deduplication.

How Immich uses its volume, for the [Immich unit](../../k8s/apps/media/immich/README.md): the upload volume is `/data` (`IMMICH_MEDIA_LOCATION`, the default), the cache volume is mounted into it with `subPath: thumbs` and `subPath: encoded-video`, so Immich sees its usual folder layout while the regenerable parts live on a dataset of their own. Immich checks each of its folders for a hidden `.immich` file and reports a missing mount ([system integrity](https://docs.immich.app/administration/system-integrity)), so a volume that fails to mount is noticed, not silently replaced by an empty folder. The mount points of the two external libraries, and the import paths set in Immich for them, must stay the same for good: Immich stores the path of every asset, and a moved path is a deleted asset plus a new one (ADR 0018, rule 3).

## Users and permissions

The account `immich` is a central one (UCS user management), with **UID `10004`**; the Immich pods run with the same user ID, see the [unit README](../../k8s/apps/media/immich/README.md#media-volumes). It has no shell. Access to the media runs through the ACL group **`fs.media-rw`** (GID `20002`), which the account is a member of. For a pure read-only access to the library the group `fs.media-ro` (GID `20003`) would be the matching one; `fs.media-rw` is kept for now because the read-only is enforced by the NFS share, and because Immich may be given write access to the external library later, for example to change `.xmp` sidecar files next to Lightroom Classic, which stays the master of the RAW files. That decision, and the group that follows from it, is part of [#2309](https://github.com/isejalabs/homelab/issues/2309).

- `upload` and `cache`: owner `immich:fs.media-rw`, set with `chown -R` as in the [datasets](#datasets) section. The NFS shares use **Mapall** (`all_squash`, `anonuid=10004`, `anongid=20002`), so every client is mapped to `immich` and `fs.media-rw`, it does not matter which user ID a container runs as, and files on `fiona` are always owned by `immich`.
- `library` and `export`: they are folders of the dataset `natascha1/data/media`, and the group `fs.media-rw` grants **write** access on that whole dataset. So `immich` can read them through the group, but there is no read-only on the filesystem level: the **NFS share option read-only** (plus the `ro` mount option and `nfs.readOnly` in the `PersistentVolume`) is what keeps Immich from changing them. Syncthing keeps writing the `prod` export as its own user. **The group entry does not work for the mapped user** (seen on `dev` on 2026-11-18: `Permission denied` on `Pictures/orig` and `Pictures/export`, although `fs.media-rw` has full rights in the ACL and is the primary group of the mapped user; the same as in [this forum thread](https://forums.truenas.com/t/nfsv4-acl-group-based-permissions-not-honored-for-mapall-user-nfs-exports-on-scale/68097), reported as NAS-144075, open when checked). The fix is a **named-user entry** for `immich`, inherited by files and folders and applied to what already exists. Done on the clones of `dev` and `qa` on 2026-11-18 (the same for `rebuild`), and the read check then passed on both:

  ```sh
  nfs4xdr_setfacl -a user:immich:rwxpDdaARWc--s:fd-----:allow /mnt/natascha1/gamma/srv/immich-copy/<env>
  nfs4xdr_winacl -a clone -rv -p /mnt/natascha1/gamma/srv/immich-copy/<env>
  ```

  The first command adds the entry to the root of the clone (flags `fd`: inherited by new files and folders), the second applies the inheritable entries of that path to everything below it. On a clone this changes the clone only. For the live library the second command rewrites the ACLs of existing files, so decide before running it on `natascha1/data/media`: a read-only entry (`r-x---a-R-c---`, as `fs.media-ro` has) is enough for the two read-only shares and gives no write right on disk, or the two shares are mapped to the account that owns the files instead of `immich`, which changes no ACL at all.
- ACL type: a thread on 25.10 reports ownership problems on datasets with the `SMB/NFSv4` ACL type ([forum](https://forums.truenas.com/t/permissions-for-user-group-from-nfsv4-acls-are-ignored-when-mounting-shares-via-nfsv4/64362)); the new `fiona2` datasets are plain ZFS datasets with the default ACL type. The existing datasets keep their ACL type.

## NFS

Services → NFS: enable **NFSv4** (NFSv3 may stay on for other clients) and switch **Require Kerberos for NFSv4 off**. While it is on, TrueNAS exports every share with `sec=krb5` whatever the share says, and the `sec=sys` mounts of the nodes fail with `Operation not permitted`. With it off, the shares that have their own security setting fall back to that one, so check the other shares with `exportfs -v` afterwards. The NFS service has to be restarted after the change, and a local test mount on `fiona` needs the loopback address in the share's hosts. Talos mounts NFS from its kubelet image, so no system extension is required ([Talos storage guide](https://docs.siderolabs.com/kubernetes-guides/csi/storage): "The NFS client is part of the kubelet image maintained by the Talos team"); NFSv4 does not use the separate lock daemon that NFSv3 needs (*verify* on the first mount). The `PersistentVolume`s mount with `nfsvers=4.1,hard,noatime,nconnect=4`: `hard` so that a NAS outage stalls the pod instead of returning I/O errors to Immich in the middle of a write, `nconnect=4` for parallel connections (*verify* that the node kernel accepts it; drop it if the mount fails). The server name in the volumes is `fiona.home.iseja.net`, which the nodes have to resolve through their DNS (*verify*).

One share per path in the [datasets table](#datasets), Shares → NFS → Add, path `/mnt/<dataset>` (for the library and the export the folder `Pictures/orig` or `Pictures/export`, inside the cloned dataset for the copies). Settings that are the same for every share: **Security `SYS`**, **Maproot** empty, **Mapall user `immich` and group `fs.media-rw`** (in `/etc/exports`: `all_squash,anonuid=10004,anongid=20002`; set on all shares of `dev` and `qa`), share enabled. The clients are listed as **Hosts**, never as a whole network: an export lists exactly the worker nodes of one environment (a pod only ever runs on a worker, and the kubelet of that node does the mount), and all six worker slots of the address scheme (`4` to `9`, see [`reference/environments.md`](../reference/environments.md#environment-id)), also those without a VM yet, so adding a worker needs no change on `fiona`.

| Environment | Hosts (worker slots 4 to 9) | `upload`, `cache` | `library`, `export` |
| --- | --- | --- | --- |
| `dev` | `10.7.8.134` to `10.7.8.139` | read-write | **Read-only** |
| `qa` | `10.7.8.124` to `10.7.8.129` | read-write | **Read-only** |
| `rebuild` | `10.7.8.174` to `10.7.8.179` | read-write | **Read-only** |
| `prod` | `10.7.8.184` to `10.7.8.189` | read-write | **Read-only** |

The addresses of the workers that exist come from the Terragrunt units (`ip` of each `machine_type = "worker"` node in `terragrunt/<tier>/eu-central-1/<env>/vehagn-k8s/terragrunt.hcl`). **When a worker is renumbered or the scheme is extended, change the Hosts of that environment's four shares**, otherwise the pod on the node cannot mount. List the current addresses:

```sh
awk '/^[[:space:]]*#/ {next} /machine_type/ {t=$3} /^[[:space:]]*ip[[:space:]]*=/ && t ~ /worker/ {print $3}' terragrunt/non-prod/eu-central-1/dev/vehagn-k8s/terragrunt.hcl
```

### Creating and changing the shares from the shell

The shares can also be made with `midclt` on `fiona`, which is faster and exact for four shares per environment. `hosts` replaces the whole list, so this also removes the loopback entries that a local test mount needed; add them again when needed. Change the hosts of all four shares of an environment (found by path, so no share ID is needed):

```sh
ENV=qa
HOSTS='["10.7.8.124","10.7.8.125","10.7.8.126","10.7.8.127","10.7.8.128","10.7.8.129"]'
midclt call sharing.nfs.query | jq -r --arg e "$ENV" '.[] | select(.path | test("/immich(-copy)?/" + $e + "/")) | .id' |
  while read -r id; do midclt call sharing.nfs.update "$id" "{\"hosts\": $HOSTS}"; done
```

Check the result against the settings in this section: `midclt call sharing.nfs.query | jq '.[] | select(.path | test("/immich")) | {id, path, hosts, ro, mapall_user, mapall_group, security}'`. A read-only flag or a missing Mapall on one share is easy to overlook, and a library share without `ro` is a share with write access (change it with `midclt call sharing.nfs.update <id> '{"ro": true}'`).

The four shares of `prod` (the live library and export need the ACL entry from [users and permissions](#users-and-permissions) first, or they list as `Permission denied`):

```sh
HOSTS='["10.7.8.184","10.7.8.185","10.7.8.186","10.7.8.187","10.7.8.188","10.7.8.189"]'
create() { midclt call sharing.nfs.create "{\"path\": \"$1\", \"comment\": \"$2\", \"hosts\": $HOSTS, \"ro\": $3, \"mapall_user\": \"immich\", \"mapall_group\": \"fs.media-rw\", \"security\": [\"SYS\"], \"enabled\": true}"; }
create /mnt/natascha1/data/srv/immich/upload "prod immich upload" false
create /mnt/fiona2/gamma/srv/immich/prod/cache "prod immich cache" false
create /mnt/natascha1/data/media/Pictures/orig "prod immich image library" true
create /mnt/natascha1/data/media/Pictures/export "prod immich rendition" true
```

The live `prod` library and export are exported **read-only to the `prod` workers only**. The `qa`, `dev` and `rebuild` shares point at the copies, so no non-prod cluster has any path to the live library or to `prod` upload data. If the live library already has an NFS share, check that the new share of the `orig` folder is accepted next to it (TrueNAS may warn about shares of nested paths; *verify*).

Network: TCP 2049 has to pass from the node VLAN to `fiona`. Kopiur already reaches `fiona` on port 9000 from the pods; NFS is a separate rule on the gateway if that VLAN is filtered (*verify*, the mount in the [test pod](#verify) shows it).

## Access from the Mac

The Mac does not mount the media library. Lightroom Classic works on a local USB SSD and the internal SSD, which Syncthing syncs with the NAS (this is how the library and the rendition tree reach `natascha1/data/media/Pictures`). So no share for the Mac is needed for Immich:

- **No access to `srv/immich`.** The `prod` upload path is accessible to the Immich service only: no SMB or other share for the Mac. (An edited copy of a phone photo goes back to Immich through its own interface, never into the folder.)
- **Direct access, if it is ever needed,** is SMB to the `media/Pictures` tree only, as for any other client; the NFS exports above do not change it.

## Snapshots

Data Protection → Periodic Snapshot Tasks. Snapshots are the undo for an accidental or Immich-made delete of an original. A task per row, **not recursive** (every dataset has its own rule), naming schema as given so that two tasks on one dataset do not expire each other's snapshots:

| Dataset | Schedule | Keep | Naming schema |
| --- | --- | --- | --- |
| `prod` upload (inside `natascha1/data`) | the existing recursive tasks of `natascha1/data`, no task of its own | as they are | as they are |
| `prod` library and export (the dataset `natascha1/data/media`) | the existing recursive tasks of `natascha1/data`, as for the rest of the library | as they are | as they are |
| `qa` (the dataset `fiona2/gamma/srv/immich/qa`, upload and cache) | daily | 7 days | `auto-daily-%Y%m%d-%H%M` |
| `dev`, `rebuild`, the clones of the library | none | | |

The owner verified on 2026-11-21 that the recursive snapshots of `natascha1/data` already include the new `prod` upload folder next to the library, so nothing is added for `prod`. The `qa` task was created on `fiona2/gamma/srv/immich/qa`.

The `qa` task exists so the snapshot restore can be exercised outside `prod`. The 30 days match Immich's own trash retention (30 days by default): a delete in Immich is first undone by the trash, a delete outside Immich by the snapshots. Snapshots live in the same pool, so they protect against deletion and bad upgrades, not against a pool failure; that is what the borgbackup is for.

## Capacity

Quotas are set by hand on the datasets and are deliberately not listed here: a table of values would drift from `fiona`, where they are changed in the UI. A runaway import must not fill a pool, so keep a quota (`refquota` is fine) on every `fiona2/gamma/srv/immich/<env>` dataset, and revisit the values after the [size test](https://github.com/isejalabs/homelab/issues/2147). The clones of the library need none: they share their blocks with the origin.

> [!WARNING]
> `fiona2` has about 1.8 TB, which is ample for all non-prod data and the `prod` cache. The pool `natascha1` had **1.40 TiB free of 5.45 TiB** in the audit of 2026-09-30. It takes the `prod` upload and its snapshots, and the **origin snapshot of the clones**: while a clone exists, the snapshot `natascha1/data/media@2144_immich-clone` cannot be destroyed and pins every block of `natascha1/data/media` that is changed or deleted afterwards. Read the current free space (`zpool list natascha1 fiona2`) before creating anything, and destroy clones and the snapshot when they are not needed.

## borgbackup

The `prod` upload dataset holds originals (it is the master for phone media, not a transit copy), so it must be in the on-site and the off-site backup. The cache datasets and everything non-prod (`fiona2`, the copies on `natascha1/gamma`) are not backed up: regenerable, or copies. The live library (`Pictures/orig`) is already part of the `fiona` backup; the rendition tree `Pictures/export` is not, because the existing exclude list names it (it is regenerable from Lightroom Classic).

`borgmatic` is a TrueNAS app (the container `ix-borgmatic-borgmatic-1`) with `/mnt/natascha1/data` and `/mnt/fiona1/data` bind-mounted read-only. Two configuration files in its `borgmatic.d` folder back up both trees, one to the on-site and one to the off-site repository, from a cron entry at 23:00 (`create prune`), with a shared exclude list (among others `**/cache/`, `**/tmp/` and `**/media/Pictures/export`). `natascha1/data/srv/immich` is a child dataset of `natascha1/data`, which the owner confirmed `borgmatic` backs up recursively (2026-11-18), so no source has to be added; `fiona2` and `natascha1/gamma` are not mounted, so the cache and the copies stay out.

> [!WARNING]
> **A child dataset created after the container started is not backed up.** The bind mount of `/mnt/natascha1/data` carries the child datasets that were mounted when the container started, with the propagation `rprivate`, so a dataset created later shows up in the container as an **empty folder**, and `borgmatic` backs up that empty folder without an error. Found on 2026-11-21: the dataset `natascha1/data/srv/immich` was created on 2026-11-19, the container had started on 2026-11-18, and the canary file was missing from the archives. After creating **any** dataset below `natascha1/data` or `fiona1/data`, restart the app (TrueNAS UI: Apps, borgmatic, Restart, or `docker restart ix-borgmatic-borgmatic-1`) when no backup is running, and check that the container sees the files:
>
> ```sh
> docker exec ix-borgmatic-borgmatic-1 ls /mnt/natascha1/data/srv/immich/upload
> ```

What is left to check, on `fiona` (the borgmatic configuration is not in this repository):

1. The `source_directories` of the on-site **and** the off-site configuration contain a path that includes `/mnt/natascha1/data/srv/immich/upload`, and no entry of the exclude list removes it.
2. The container sees the files of the child dataset, see the warning above. The restore check in [Verify](#verify) proves both points.
3. Do not add `fiona2` or `natascha1/gamma` to the sources: that would pull in the cache and the copies.
4. Backup order matters for Immich: back up the database first, the files second, so that the worst case is a file the database does not know, not the reverse ([Immich backup and restore](https://docs.immich.app/administration/backup-and-restore)). Immich's own database dumps are in `upload/backups/`, so they are included; the CloudNativePG dump to RustFS ([#2145](https://github.com/isejalabs/homelab/issues/2145)) should finish before the borg run starts (*verify* the schedules once both exist).

## Copies of the library for non-prod

Non-prod environments get **ZFS clones** of the dataset `natascha1/data/media`, never the live data. A clone costs no space until it differs from its origin and is made in seconds. The cost is that a clone is the **whole dataset** (every folder in it, not only the library and its export), because the dataset is the unit of a clone, not a sub-folder. The clone has to be in the same pool as its origin, so it is on `natascha1`, not on `fiona2`. Nothing is deleted from the clones: the environments simply see the full data, read-only through the NFS share. To keep a test environment small, limit what Immich scans (the import path and the exclusion patterns of the external library in Immich, [#2146](https://github.com/isejalabs/homelab/issues/2146)), not the files on `fiona`.

Made by the owner on 2026-11-18 for `dev` and `qa`; `rebuild` gets the same, `prod` needs none:

```sh
# one origin snapshot for all clones, named so that no periodic snapshot task owns or expires it
zfs snapshot natascha1/data/media@2144_immich-clone
zfs create natascha1/gamma/srv/immich-copy
zfs set refquota=100G natascha1/gamma/srv/immich-copy
zfs clone natascha1/data/media@2144_immich-clone natascha1/gamma/srv/immich-copy/dev
zfs clone natascha1/data/media@2144_immich-clone natascha1/gamma/srv/immich-copy/qa
```

The NFS shares are folders of the clones, `/mnt/natascha1/gamma/srv/immich-copy/<env>/Pictures/orig` and `.../Pictures/export`, the same relative paths as the live ones, see [NFS](#nfs).

Re-establishing a copy: destroy the clone (`zfs destroy natascha1/gamma/srv/immich-copy/<env>`), then make a new snapshot and clone it; the old snapshot can only be destroyed when no clone uses it any more. Because the copies live apart from `fiona2/gamma/srv/immich/<env>`, this never touches the data Immich wrote in that environment. The paths in Immich stay the same, so the external libraries keep their assets.

The Lightroom catalog copy for the proof of concept stays on the Mac; it is not part of any export.

## Verify

These are the acceptance criteria of [#2144](https://github.com/isejalabs/homelab/issues/2144). Run the first on `dev` and on `qa`, the second on any environment with snapshots (`qa`), the third once for `prod`.

1. **Mounts, read-write and read-only.** With the `immich` unit applied in the environment (merged, or [`track-branch`](../../.agents/skills/track-branch/SKILL.md) on `dev`), apply the test pod and read its result:

   ```sh
   kubectl --context admin@dev-homelab apply -f k8s/test/storage/test-nfs-immich-media.yaml
   kubectl --context admin@dev-homelab -n immich logs test-nfs-immich-media
   kubectl --context admin@dev-homelab delete -f k8s/test/storage/test-nfs-immich-media.yaml
   ```

   Expected: `OK` for `upload` and `cache` writable, and for `library` and `export` both `read-only` and `readable`, and the `mount` lines show `nfs4` with `ro` on the two read-only ones. A `FAIL ... not readable` on a read-only volume means the mapped user `immich` cannot read the files: see [permissions](#users-and-permissions). A pod stuck in `ContainerCreating` is a mount problem: `kubectl describe pod` shows the NFS error (export hosts, firewall, name resolution).
2. **Restore a deleted file from a snapshot.** On `fiona`, with a `qa` snapshot task running (or a manual snapshot); the snapshot is of the dataset `fiona2/gamma/srv/immich/qa`, so the file is found below `upload/` in it:

   ```sh
   echo canary > /mnt/fiona2/gamma/srv/immich/qa/upload/snapshot-test.txt
   zfs snapshot fiona2/gamma/srv/immich/qa@manual-test
   rm /mnt/fiona2/gamma/srv/immich/qa/upload/snapshot-test.txt
   cp /mnt/fiona2/gamma/srv/immich/qa/.zfs/snapshot/manual-test/upload/snapshot-test.txt /mnt/fiona2/gamma/srv/immich/qa/upload/
   zfs destroy fiona2/gamma/srv/immich/qa@manual-test
   rm /mnt/fiona2/gamma/srv/immich/qa/upload/snapshot-test.txt
   ```

   Expected: the `cp` finds the file in the snapshot and the content is `canary`.
3. **Restore a file from the borg repositories.** Put a canary file with some content (`date > <file>`, an empty file makes the comparison meaningless) next to Immich's folders in the `prod` upload folder, for example `/mnt/natascha1/data/srv/immich/upload/issue-2144-foo-backup-test`, and check that the container sees it (`docker exec ix-borgmatic-borgmatic-1 ls /mnt/natascha1/data/srv/immich/upload`; if the folder is empty or missing, restart the app first, see [borgbackup](#borgbackup)). Then wait for the next backup run at 23:00, or start the on-site one by hand (about 15 minutes for the whole tree): `docker exec ix-borgmatic-borgmatic-1 borgmatic -c /etc/borgmatic.d/<on-site configuration file> create --stats -v 1`. `borgmatic` runs as the container `ix-borgmatic-borgmatic-1` on `fiona` (the name in the `NAMES` column of `docker ps`, so no container ID is needed; TrueNAS names an app container `ix-<app>-<service>-1`). Look at the repositories and the archives, then search for the canary in the newest archives of every configured repository, the on-site and the off-site one:

   ```sh
   docker exec ix-borgmatic-borgmatic-1 borgmatic repo-list
   docker exec ix-borgmatic-borgmatic-1 borgmatic list --find issue-2144-foo-backup-test --last 3
   ```

   The second command prints the path of the file as it is stored in each archive that contains it, per repository. Then extract it from one repository (`--repository` takes the path as `repo-list` shows it (quoted globs work), and is needed as soon as more than one repository is configured) into a scratch directory of the container, which has to exist, never over the live data, and compare:

   ```sh
   docker exec ix-borgmatic-borgmatic-1 mkdir -p /tmp/borg-restore
   docker exec ix-borgmatic-borgmatic-1 borgmatic extract --repository <repository> --archive latest --path <path from the list> --destination /tmp/borg-restore
   docker exec ix-borgmatic-borgmatic-1 sh -c 'cmp /tmp/borg-restore/<path from the list> /mnt/natascha1/data/srv/immich/upload/issue-2144-foo-backup-test && echo identical'
   docker exec ix-borgmatic-borgmatic-1 rm -r /tmp/borg-restore
   ```

   Expected: the canary is listed in both repositories (a repository that is unreachable shows up as an error in `/var/log/borgmatic.log` inside the container, in the folder `log` of the app's data) and `identical` is printed, with the files of the child dataset visible, not an empty folder. If `cmp` cannot find the live file, the container has the data mounted under a different path; `borgmatic list` and the `source_directories` of its configuration show which. After the first real uploads, repeat the check once with a real asset, and remove the canary afterwards.

## Monitoring

`fiona` already has the Checkmk agent. Run a service discovery on the host after the datasets exist and check that the new datasets show up as filesystem services, set the usage thresholds on `prod` upload, and add the fill level of the non-prod datasets as a warning only (*verify* what the existing ZFS dataset check on `fiona` reports, see the [RustFS capacity audit](../audits/2026-10-rustfs-capacity.md)). The RustFS quota monitoring in [`terragrunt/README.md`](../../terragrunt/README.md) is unrelated to these datasets.

## Open owner inputs

Decided and confirmed by the owner (2026-11-18 and 2026-11-21): the dataset layout, the user `immich` (`10004`) and the group `fs.media-rw` (`20002`) with Mapall on the shares, `borgmatic` backing up `/mnt/natascha1/data` recursively, the Mac not mounting the media (Syncthing, see [Mac access](#access-from-the-mac)), snapshots (`qa` task created, `prod` covered by the recursive tasks of `natascha1/data`). What is left:

1. **The four `prod` shares and the ACL entry on the live library:** see [creating and changing the shares](#creating-and-changing-the-shares-from-the-shell) and [users and permissions](#users-and-permissions); the live library needs the decision on a read-only entry or a mapping to the file owner first.
2. **Group and write access for the external libraries:** `fs.media-rw` or `fs.media-ro`, and whether Immich gets write access for `.xmp` sidecars, decided with [#2309](https://github.com/isejalabs/homelab/issues/2309).
3. **Pool capacity** of `natascha1` (`prod` upload growth, snapshots, the origin snapshot pinned by the clones); `fiona2` has about 1.8 TB, which is enough (see the warning under [capacity](#capacity)).
4. **Restore checks:** the snapshot restore (Verify 2) and the borg restore (Verify 3) prove the protection; Verify 3 also proves that the backup contains `natascha1/data/srv/immich` with the files of a child dataset, not an empty directory.

## Related

- [ADR 0018](../decisions/0018-media-source-of-truth.md): the media model this storage implements
- [`k8s/apps/media/immich`](../../k8s/apps/media/immich/README.md): the Kubernetes side, static NFS volumes
- [`k8s/test/storage/test-nfs-immich-media.yaml`](../../k8s/test/storage/test-nfs-immich-media.yaml): the mount test
- [CSI alternatives (#455)](https://github.com/isejalabs/homelab/issues/455): why a static volume is enough here
