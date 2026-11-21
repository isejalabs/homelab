# Immich

Immich is the photo and video archive that replaces Lightroom Mobile for phone uploads. So far this unit holds only its media storage: static NFS volumes on the NAS `fiona` and their claims; the application itself follows in [#2146](https://github.com/isejalabs/homelab/issues/2146).

## At a glance

| | |
| --- | --- |
| Namespace | `immich` |
| Runs in | `dev`, `qa`, `rebuild` (Flux set `qa-soaking`); `prod` follows with the promotion ([#2149](https://github.com/isejalabs/homelab/issues/2149)), which moves the unit out of that set |
| Installed via | raw manifests: four static NFS `PersistentVolume`s and their `PersistentVolumeClaim`s (no CSI driver); the namespace comes from [`immich-db`](../immich-db/README.md) |
| Flux Kustomization | `immich`, depends on `immich-db` |

## Purpose

Immich becomes the online archive for all family photos and videos, kept on the NAS `fiona` and run in Kubernetes ([#413](https://github.com/isejalabs/homelab/issues/413)). Who owns which media is decided in [ADR 0018](../../../../docs/decisions/0018-media-source-of-truth.md): Immich owns phone uploads, Lightroom Classic owns the existing library, which Immich only reads. This unit provides the storage for that, as plain NFS volumes: the database never goes on NFS, it stays on Longhorn ([#2145](https://github.com/isejalabs/homelab/issues/2145)).

## Where it is used

- **Used by**: the Immich server and its jobs, once [#2146](https://github.com/isejalabs/homelab/issues/2146) adds them to this unit. Until then only the [mount test](../../../test/storage/test-nfs-immich-media.yaml) uses the claims.
- **Depends on**: the TrueNAS side on `fiona` (datasets, NFS exports restricted to the environment's worker nodes, snapshots, borgbackup), which is configured by hand and documented in [`immich-media-storage.md`](../../../../docs/operations/immich-media-storage.md); the nodes' own NFS client (part of the Talos kubelet image, no extension).

## Access

Not exposed. There is no `Service` yet; the web UI, its hostname and the login come with the application itself, see [Purpose](#purpose).

## Updates

Nothing is versioned here. The export paths are in [`envs/<env>/kustomization.yaml`](envs) and have to stay in step with the dataset names in [`immich-media-storage.md`](../../../../docs/operations/immich-media-storage.md#datasets). The `ENV` placeholder in `base/` is never applied; `dbg`, `head`, `poc` and `src` have no datasets and do not run the unit.

## Operations

- TrueNAS settings, snapshots, borgbackup, restore checks: [`immich-media-storage.md`](../../../../docs/operations/immich-media-storage.md); the ACL entry that lets the mapped user read the library and export is under [users and permissions](../../../../docs/operations/immich-media-storage.md#users-and-permissions).
- Mount and permission check: [`test-nfs-immich-media.yaml`](../../../test/storage/test-nfs-immich-media.yaml), described under [Verify](../../../../docs/operations/immich-media-storage.md#verify).
- The volumes are not backed up by kopiur (it snapshots CSI volumes, not NFS): protection is ZFS snapshots and the borgbackup of the `prod` upload dataset on `fiona`.

## Cheat sheet

```sh
# the volumes and their binding
kubectl --context admin@dev-homelab get pv,pvc -n immich | grep immich

# why a pod cannot mount (export hosts, firewall, name resolution)
kubectl --context admin@dev-homelab -n immich describe pod <pod>

# check that the Flux Kustomization is ready
flux --context admin@dev-homelab get ks immich
```

## Media volumes

Static `PersistentVolume`s, pinned to their claims by `claimRef` and `volumeName` (`storageClassName: ""`, so no dynamic provisioning), reclaim policy `Retain`, mounted with `nfsvers=4.1,hard,noatime,nconnect=4`. The server is `fiona.home.iseja.net`. The capacity on the objects is nominal; the limit is the ZFS quota of the dataset.

| Claim | Mode | Mount in the Immich pod | Path on `fiona` (`prod`; non-prod in the runbook) |
| --- | --- | --- | --- |
| `immich-upload` | read-write | `/data` (`IMMICH_MEDIA_LOCATION`, the default) | `natascha1/data/srv/immich/upload` (non-prod: the directory `upload` of `fiona2/gamma/srv/immich/<env>`) |
| `immich-cache` | read-write | `/data/thumbs` with `subPath: thumbs` and `/data/encoded-video` with `subPath: encoded-video` | the directory `cache` of `fiona2/gamma/srv/immich/<env>` (all environments) |
| `immich-library` | **read-only** | a fixed path such as `/external/library`, set as the import path of the external library | the live Lightroom library `natascha1/data/media/Pictures/orig` (non-prod: the folder `orig` of a ZFS clone of `natascha1/data/media` under `natascha1/gamma/srv/immich-copy/<env>`) |
| `immich-export` | **read-only** | a fixed path such as `/external/export`, the second external library | the folder `natascha1/data/media/Pictures/export`, written from the Mac (non-prod: the folder `export` of the clone) |

The export path of a volume is always `/mnt/<path>`. The full dataset table, per environment, is in [`immich-media-storage.md`](../../../../docs/operations/immich-media-storage.md#datasets); the videos-only library is not part of the proof of concept yet.

For [#2146](https://github.com/isejalabs/homelab/issues/2146), who wires the pods:

- Run the Immich pods as **UID `10004`** and **GID `20002`**, the `immich` account (central user management) and its group `fs.media-rw`. The NFS shares map every client to them (`all_squash`), so this only keeps what `ls` shows consistent. Verify that the images work as non-root.
- Mount the two external libraries with `readOnly: true` as well, and never at another path later: Immich stores the path of every asset, a moved path is a deleted asset plus a new one.
- Immich writes a hidden `.immich` file into each of its folders and reports a missing mount; do not set `IMMICH_IGNORE_MOUNT_CHECK_ERRORS`.
- The unit is not in `prod` yet: with [#2149](https://github.com/isejalabs/homelab/issues/2149) it moves from `qa-soaking` into `prod`'s own composition ([`envs/prod`](envs/prod/kustomization.yaml) already has the real paths).

## Upstream

- Homepage and documentation: <https://immich.app/>
- Source and releases: <https://github.com/immich-app/immich>
- Kubernetes install notes: <https://docs.immich.app/install/kubernetes>
