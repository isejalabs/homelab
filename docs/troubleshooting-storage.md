---
status: current
---

# Troubleshooting: storage (PVCs, Longhorn, proxmox-csi)

For whoever's responding to a "volume won't bind" or "volume is degraded" incident — not an introduction to Longhorn vs. proxmox-csi (see [`architecture/storage.md`](architecture/storage.md) for that) and not app-data backup/restore (see [`kopiur-backup-restore.md`](kopiur-backup-restore.md) for that).

## 1. A PVC stuck `Pending`

**Check this isn't expected behavior before treating it as stuck.** Every Longhorn `StorageClass` in this repo sets `volumeBindingMode: WaitForFirstConsumer` (see [`storage.md`](architecture/storage.md#storageclasses--one-driver-several-tradeoff-profiles)) — a freshly created PVC legitimately stays `Pending` until a Pod that actually claims it is scheduled. Check the owning Pod first:

```sh
kubectl get pod -n <namespace> -o wide
```

If the Pod itself is `Pending` (not yet scheduled), that's the real problem to diagnose — Pod scheduling (resources, node affinity/taints), not the PVC. The PVC will bind on its own once the Pod schedules.

If a Pod **is** running/scheduled and the PVC is still `Pending`, get the actual provisioning error:

```sh
kubectl describe pvc <name> -n <namespace>
```

Read the `Events` section at the bottom — a CSI driver that isn't ready, a `storageClassName` typo, or exhausted capacity all show up there, not in the PVC's `status` fields.

### proxmox-csi specifically

Confirm the driver has capacity and is actually running (real example output from [`k8s/infra/csi-proxmox/proxmox-csi/README.md`](../k8s/infra/csi-proxmox/proxmox-csi/README.md)):

```sh
kubectl get csistoragecapacities -ocustom-columns=CLASS:.storageClassName,AVAIL:.capacity,ZONE:.nodeTopology.matchLabels -A
kubectl get pods -n csi-proxmox
```

Remember proxmox-csi volumes in this repo are **Terragrunt-pinned, not dynamically provisioned** (see [`storage.md`](architecture/storage.md#proxmox-csi--terragrunt-pinned-volumes-that-survive-a-cluster-rebuild)) — a PVC referencing one by `volumeName` failing to bind is more likely a mismatch between what the PVC expects and what Terragrunt actually created/imported than a transient driver issue. See [`terragrunt/README.md`](../terragrunt/README.md) for the actual import commands rather than re-deriving them here.

## 2. A Longhorn volume degraded or faulted

```sh
kubectl get volumes.longhorn.io -n longhorn-system
```

Check the `ROBUSTNESS` column — **Degraded** means at least one replica is unhealthy but the volume is still serving reads/writes from the remaining healthy replica(s); **Faulted** means none are, which is a real data-availability problem, not just a resilience one. List the individual replicas to see which node/disk is actually unhealthy:

```sh
kubectl get replicas.longhorn.io -n longhorn-system -l longhornvolume=<volume-name>
```

Common underlying causes, in order of likelihood: a node down or cordoned (`kubectl get nodes`), or the node's Longhorn data disk full (`defaultDataPath: /var/mnt/longhorn` per [`storage.md`](architecture/storage.md#longhorn--ordinary-in-cluster-dynamic-storage) — check with `df -h /var/mnt/longhorn` on that node, e.g. via `talosctl` or a debug pod). Fix the underlying node/disk problem first — Longhorn rebuilds a missing/unhealthy replica automatically once the node or disk it needs is healthy again; there's normally no direct action needed on the `Volume`/`Replica` objects themselves.

## 3. `reclaimPolicy: Retain` leaks — the most common self-inflicted cause

Both storage backends in this repo use `reclaimPolicy: Retain` everywhere, deliberately (see [`storage.md`](architecture/storage.md#reclaimpolicy-retain-and-the-two-step-cleanup-gotcha)) — deleting a PVC or its namespace never deletes the underlying volume. If a volume "should" be free but a new PVC can't claim it, check for an orphaned `PersistentVolume` left behind by an earlier deleted PVC/namespace (e.g. leftover from [`track-branch`](../.agents/skills/track-branch/SKILL.md) testing on a non-prod environment):

```sh
kubectl get pv
```

For Longhorn, cleanup is a **two-object** job — both the `PersistentVolume` and the matching `volumes.longhorn.io` object need deleting, or the disk space and the Longhorn volume record both leak:

```sh
kubectl delete pv <name>
kubectl delete volumes.longhorn.io <name> -n longhorn-system
```

For proxmox-csi, the equivalent cleanup is the Terragrunt state-removal flow in [`terragrunt/README.md`](../terragrunt/README.md#prevent-deletion-of-proxmox-volumes), not a plain `kubectl delete` — these volumes are Terragrunt-managed, so removing just the Kubernetes object without updating Terraform state leaves it dangling there instead.

## Verify the fix actually took

- PVC case: `kubectl get pvc <name> -n <namespace>` shows `Bound`, and the owning Pod actually starts (`kubectl get pod -n <namespace>` → `Running`) — a `Bound` PVC with a Pod still stuck elsewhere means the storage issue is fixed but something else isn't.
- Longhorn case: re-check `kubectl get volumes.longhorn.io -n longhorn-system` shows `ROBUSTNESS: Healthy`, not just that the node/disk problem is gone — a rebuild can take a while after the underlying cause clears.
