# Longhorn vs. proxmox-csi

## Status

current

## Context

proxmox-csi was the only storage mechanism from the very start of the Kubernetes journey (first PVC pattern present by 2024-12-08) — statically-named, Terragrunt-pinned `PersistentVolume`s (e.g. `pv-mongodb`, `pv-unifi`) backed directly by Proxmox-side disks. Longhorn came much later (first draft 2025-09-16, real implementation 2026-03/04) once the app set had grown enough to need ordinary, dynamically-provisioned, replicated storage without hand-wiring a Terragrunt volume for every new PVC.

proxmox-csi has real drawbacks that motivated the move: no backup/snapshotting of its own (only recent Proxmox versions have started adding this at all), and a volume is pinned to wherever its backing Proxmox disk lives — a pod using one can't be rescheduled onto another node the way a replicated Longhorn volume's pod can.

proxmox-csi's one real advantage — a volume's backing disk survives a full cluster rebuild via Terraform state exclusion/re-import (see [`storage.md`](../architecture/storage.md#proxmox-csi--terragrunt-pinned-volumes-that-survive-a-cluster-rebuild)) — used to be exclusive to it. It no longer is: [kopiur](../kopiur-backup-restore.md) (adopted later still, see [issue #807](https://github.com/isejalabs/homelab/issues/807)) now gives Longhorn volumes their own rebuild-survival story too, via backup/restore rather than Terraform import. The CSI driver's author ([sergelogvinov](https://github.com/sergelogvinov/proxmox-csi-plugin)) also claims better raw performance for proxmox-csi — not independently tested or verified here, so treated as an unconfirmed claim rather than a decided advantage.

## Options considered

- **proxmox-csi only (rejected as the sole mechanism)** — every new app's storage need would require a Terragrunt-declared volume (see [ADR 0003](0003-terragrunt.md)) before it could even get a PVC, no in-cluster replication, no node-mobility for the pod using it, and no backup/snapshotting of its own.
- **Longhorn only (rejected for every volume)** — ordinary dynamic, replicated storage, but before kopiur existed this meant giving up rebuild-survival entirely for any volume that needed it.
- **Both, split by which property a given volume actually needs (chosen).**

## Decision

Longhorn is the default for new workloads — ordinary app storage, provisioned on demand, replicated for HA at the storage layer (five custom `StorageClass`es plus the chart's own implicit default, see [`storage.md`](../architecture/storage.md#storageclasses--one-driver-several-tradeoff-profiles)). No new volume is provisioned on proxmox-csi today, but the driver itself stays installed rather than being removed: it's inbuilt into the `terraform-proxmox-talos` module already (low cost to keep running), and is kept available for a potential future workload (e.g. a database) where its claimed performance characteristics might actually matter — not yet needed, not yet tested.

## Consequences

- Two storage backends to understand and operate instead of one — see [`storage.md`](../architecture/storage.md#reclaimpolicy-retain-and-the-two-step-cleanup-gotcha) and [`troubleshooting-storage.md`](../troubleshooting-storage.md) for the operational overlap/divergence this creates (e.g. `reclaimPolicy: Retain` cleanup is a two-object job for Longhorn, a Terragrunt-state job for proxmox-csi).
- proxmox-csi's footprint is expected to keep shrinking rather than growing (see [issue #80](https://github.com/isejalabs/homelab/issues/80), open) — this isn't a permanent split, and no currently-planned app is expected to need a new proxmox-csi volume.
- If proxmox-csi's performance claim ever becomes decision-relevant (e.g. for a database workload), it would need to actually be tested against this homelab's own hardware/storage pool before being trusted.

## Open decisions

- A third proxmox-csi drawback was flagged during drafting but not fully captured — worth revisiting what it was.
