# Immich

Immich is the photo and video archive that replaces Lightroom Mobile for phone uploads. So far this unit holds only its media storage: namespace, static NFS volumes on the NAS `fiona` and their claims; the application itself follows in [#2146](https://github.com/isejalabs/homelab/issues/2146).

## At a glance

| | |
| --- | --- |
| Namespace | `immich` |
| Runs in | `dev`, `qa`, `rebuild` (no Flux set, registered in [`flux/envs`](../../../bootstrap/cluster/flux/envs) of each); `prod` follows with the promotion ([#2149](https://github.com/isejalabs/homelab/issues/2149)) |
| Installed via | raw manifests: a `Namespace`, four static NFS `PersistentVolume`s and their `PersistentVolumeClaim`s (no CSI driver) |
| Flux Kustomization | `immich`, no `dependsOn` |

## Purpose

Immich becomes the online archive for all family photos and videos, kept on the NAS `fiona` and run in Kubernetes ([#413](https://github.com/isejalabs/homelab/issues/413)). Who owns which media is decided in [ADR 0018](../../../../docs/decisions/0018-media-source-of-truth.md): Immich owns phone uploads, Lightroom Classic owns the existing library, which Immich only reads. This unit provides the storage for that, as plain NFS volumes: the database never goes on NFS, it stays on Longhorn ([#2145](https://github.com/isejalabs/homelab/issues/2145)).

## Where it is used

- **Used by**: the Immich server and its jobs, once [#2146](https://github.com/isejalabs/homelab/issues/2146) adds them to this unit. Until then only the [mount test](../../../test/storage/test-nfs-immich-media.yaml) uses the claims.
- **Depends on**: the TrueNAS side on `fiona` (datasets, NFS exports restricted to the environment's worker nodes, quotas, snapshots, borgbackup), which is configured by hand and documented in [`immich-media-storage.md`](../../../../docs/operations/immich-media-storage.md); the nodes' own NFS client (part of the Talos kubelet image, no extension).

## Access

Not exposed. There is no `Service` yet; the web UI, its hostname and the login come with the application itself, see [Purpose](#purpose).

## Updates

Nothing is versioned here. The export paths are in [`envs/<env>/kustomization.yaml`](envs) and have to stay in step with the dataset names in [`immich-media-storage.md`](../../../../docs/operations/immich-media-storage.md#datasets). The `ENV` placeholder in `base/` is never applied; `dbg`, `head`, `poc` and `src` have no datasets and do not run the unit.

## Operations

- TrueNAS settings, snapshots, borgbackup, restore checks: [`immich-media-storage.md`](../../../../docs/operations/immich-media-storage.md).
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

| Claim | Mode | Mount in the Immich pod | Dataset |
| --- | --- | --- | --- |
| `immich-upload` | read-write | `/data` (`IMMICH_MEDIA_LOCATION`, the default) | `natascha1/immich/<env>/upload` |
| `immich-cache` | read-write | `/data/thumbs` with `subPath: thumbs` and `/data/encoded-video` with `subPath: encoded-video` | `natascha1/immich/<env>/cache` |
| `immich-library` | **read-only** | a fixed path such as `/external/library`, set as the import path of the external library | the live Lightroom library (`prod`), a copy elsewhere |
| `immich-renditions` | **read-only** | a fixed path such as `/external/renditions`, the second external library | a rendition dataset (`prod`), a copy elsewhere |

For [#2146](https://github.com/isejalabs/homelab/issues/2146), who wires the pods:

- Run the Immich pods as **UID and GID `3100`**, the numbers of the `immich` account on `fiona`. The NFS shares map every client to that account, so this only keeps what `ls` shows consistent. Verify that the images work as non-root.
- Mount the two external libraries with `readOnly: true` as well, and never at another path later: Immich stores the path of every asset, a moved path is a deleted asset plus a new one.
- Immich writes a hidden `.immich` file into each of its folders and reports a missing mount; do not set `IMMICH_IGNORE_MOUNT_CHECK_ERRORS`.
- Register the unit in `prod` only with [#2149](https://github.com/isejalabs/homelab/issues/2149), after replacing the two placeholder paths in [`envs/prod`](envs/prod/kustomization.yaml) with the real datasets.

## Upstream

- Homepage and documentation: <https://immich.app/>
- Source and releases: <https://github.com/immich-app/immich>
- Kubernetes install notes: <https://docs.immich.app/install/kubernetes>
