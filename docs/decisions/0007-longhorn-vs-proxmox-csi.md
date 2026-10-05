# Longhorn vs. proxmox-csi

## Status

current

## Context

proxmox-csi was the only storage mechanism from the very start of the Kubernetes journey (first PVC pattern present by 2024-12-08) — statically-named, Terragrunt-pinned `PersistentVolume`s (e.g. `pv-mongodb`, `pv-unifi`) backed directly by Proxmox-side disks. Longhorn came much later (first draft 2025-09-16, real implementation 2026-03/04) once the app set had grown enough to need ordinary, dynamically-provisioned, replicated storage without hand-wiring a Terragrunt volume for every new PVC.

## Options considered

- **proxmox-csi only (rejected as the sole mechanism)** — every new app's storage need would require a Terragrunt-declared volume (see [ADR 0003](0003-terragrunt.md)) before it could even get a PVC, and gives no in-cluster replication — durability depends entirely on the underlying Proxmox disk.
- **Longhorn only (rejected for every volume)** — ordinary dynamic, replicated storage, but gives up the one property proxmox-csi's static pinning provides: a volume's backing disk survives a full cluster teardown/rebuild via Terraform state exclusion/re-import, independent of Longhorn's own backup/restore path (see [`storage.md`](../architecture/storage.md#proxmox-csi--terragrunt-pinned-volumes-that-survive-a-cluster-rebuild)).
- **Both, split by which property a given volume actually needs (chosen).**

## Decision

Longhorn is the default for new workloads — ordinary app storage, provisioned on demand, replicated for HA at the storage layer (five custom `StorageClass`es plus the chart's own implicit default, see [`storage.md`](../architecture/storage.md#storageclasses--one-driver-several-tradeoff-profiles)). proxmox-csi is kept only for the handful of volumes that predate the move to Longhorn and specifically need to survive a full cluster rebuild by Terraform import rather than Longhorn's own backup/restore ([kopiur](../kopiur-backup-restore.md), adopted later still, see [issue #807](https://github.com/isejalabs/homelab/issues/807)).

## Consequences

- Two storage backends to understand and operate instead of one — see [`storage.md`](../architecture/storage.md#reclaimpolicy-retain-and-the-two-step-cleanup-gotcha) and [`troubleshooting-storage.md`](../troubleshooting-storage.md) for the operational overlap/divergence this creates (e.g. `reclaimPolicy: Retain` cleanup is a two-object job for Longhorn, a Terragrunt-state job for proxmox-csi).
- New app storage defaults to Longhorn without a per-app Terragrunt change — only a volume that explicitly needs rebuild-survival independent of kopiur gets the proxmox-csi treatment.
- proxmox-csi's footprint is expected to keep shrinking as kopiur-backed Longhorn proves itself (see [issue #80](https://github.com/isejalabs/homelab/issues/80), open) — this isn't a permanent 50/50 split.
