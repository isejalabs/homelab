# Kopiur Backup & Restore

## Overview

[kopiur](https://github.com/home-operations/kopiur) is the Kubernetes-native backup operator used in this cluster. It snapshots PVC data via CSI `VolumeSnapshot`s, uploads it with [kopia](https://kopia.io) (a content-addressable, deduplicating backup engine) to an S3-compatible repository, and can populate new PVCs from those backups via the standard Kubernetes CSI PVC-populator mechanism.

- **Repository**: `fiona`, a `ClusterRepository` pointing at this cluster's S3-compatible NAS (`fiona.home.iseja.net:9000`), with a separate bucket per environment (`<env>-kopiur-backup`).
- **Wiring an app up**: include the `kopiur-backup` component (`k8s/components/apps/kopiur/backup`) in the app's `base/kustomization.yaml`. It pulls in the `kopiur-secret` component automatically — no separate reference needed, and no per-env patching either (see [Automatic per-env credentials](#automatic-per-env-credentials) below). See [k8s/components/apps/kopiur/README.md](../k8s/components/apps/kopiur/README.md) for what each component does.
- **Two independent backup layers exist.** Longhorn's own native `RecurringJob`s (`k8s/infra/longhorn-system/longhorn/base/job-*.yaml`) already give *every* Longhorn volume an hourly local snapshot plus daily/weekly/monthly offsite backups automatically, with zero per-app setup. kopiur adds a finer-grained (hourly, offsite) layer on top, but only for apps explicitly opted in via the component above. Once an app is on kopiur, it's covered by both — that's deliberate defense-in-depth, not redundant waste, since the two fail independently (see the [PR discussion](https://github.com/isejalabs/homelab/pull/1121) for why).

## How it works

### Automatic restore when an app's PVC is (re)created

An app's PVC has `dataSourceRef` pointing at a `Restore` object. `Restore.spec.target.populator: {}` uses the CSI PVC-populator mechanism: when a PVC referencing it is created, kopiur automatically restores the latest matching snapshot into it *before* any pod can mount it — kubelet just waits.

This is why deleting a PVC and letting it get recreated (a deliberate `kubectl delete pvc`, or a full namespace recreation) transparently restores the app's data with no explicit "restore" command needed for the common "the volume got deleted/lost and needs to come back" case.

### Automatic empty-volume creation when there's no backup yet

On an app's very first deploy, no snapshot exists yet for its identity. `Restore.spec.policy.onMissingSnapshot: Continue` tells kopiur to populate an empty volume instead of blocking forever waiting for a snapshot that will never arrive. Confirmed live: a brand-new app's PVC binds and its pod starts immediately, no manual intervention needed.

### Ongoing protection

A `SnapshotSchedule` fires hourly (`cron: H * * * *`) per app, creating a `Snapshot` object. That `Snapshot`:
1. Takes a CSI `VolumeSnapshot` of the source PVC.
2. Restores it into a temporary staging PVC (`longhorn-scratch-ext4`/`longhorn-scratch-xfs` — fast, single-replica, disposable; **must match the source PVC's filesystem**, since a `VolumeSnapshot` restore is a raw block copy, not a reformat).
3. Runs the kopia mover, which reads the staging PVC and uploads to `fiona`.
4. Deletes the staging PVC automatically once done (confirmed: no accumulation from routine hourly operation, only from the app itself being deleted/recreated repeatedly, which orphans the *data* PVC's old `Retain`-policy volume, not the staging one).

Retention is GFS-style (`SnapshotPolicy.spec.retention`: `keepLatest` / `keepHourly` / `keepDaily` / `keepWeekly`) — old snapshots beyond those counts are pruned automatically; no manual cleanup needed for normal operation.

## Daily tasks (manual, for now)

> [!NOTE]
> A `just kopiur::*` recipe set (snapshot listing, manual backup, restore choreography) exists as a draft on the `feat/kopiur-just-recipes` branch and will land as its own PR. Until then, here's the manual equivalent — worth knowing regardless, since the recipes will just be thin wrappers around exactly these commands.

### List all available backups (snapshots) of an app

```sh
❯ kubectl get snapshot -n <namespace> -l kopiur.home-operations.com/config=<app> \
    -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,ORIGIN:.status.origin,KOPIA_ID:.status.snapshot.kopiaSnapshotID,SIZE:.status.stats.sizeBytes,CREATED:.metadata.creationTimestamp
```

### Trigger a manual backup

```sh
❯ kubectl create -f - <<EOF
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Snapshot
metadata:
  generateName: <app>-manual-
  namespace: <namespace>
spec:
  policyRef:
    name: <app>
  description: "manual backup"
EOF

❯ kubectl get snapshot -n <namespace> -w   # watch it progress: Pending -> Running -> Succeeded
```

### Restore an app from its latest backup

kopiur's `Restore` is a CSI populator — it only fires once, at PVC creation. There's no "roll this existing volume back in place"; restoring means deleting the PVC and letting a fresh one populate. Flux actively reverts manual changes (a scaled-down Deployment gets scaled back up on its next reconcile), so the owning Flux object must be suspended first.

1. **Determine ownership** — check the Deployment's own labels:
   ```sh
   ❯ kubectl get deploy <app> -n <namespace> -o jsonpath='{.metadata.labels}'
   ```
   A plain-manifest app carries `kustomize.toolkit.fluxcd.io/name` directly; a Helm-based app carries `helm.toolkit.fluxcd.io/name` instead (one hop further removed — the Kustomization created the HelmRelease, which created the Deployment).
2. **Suspend it:**
   ```sh
   ❯ flux suspend kustomization <name>       # or: flux suspend helmrelease <name> -n <namespace>
   ```
3. **Scale down and wait for the pod to go away:**
   ```sh
   ❯ kubectl scale deployment <app> -n <namespace> --replicas=0
   ❯ kubectl wait pod -l app=<app> -n <namespace> --for=delete --timeout=120s
   ```
4. **Delete the PVC:**
   ```sh
   ❯ kubectl delete pvc <app> -n <namespace>
   ```
5. **Resume** — this recreates the PVC (populated from the latest snapshot) *and* scales the Deployment back up in the same reconcile, no separate scale-up step needed:
   ```sh
   ❯ flux resume kustomization <name>        # or: flux resume helmrelease <name> -n <namespace>
   ❯ flux reconcile kustomization <name>     # or: flux reconcile helmrelease <name> -n <namespace> --with-source --force
   ```
6. **Wait for the PVC to bind:**
   ```sh
   ❯ kubectl get pvc <app> -n <namespace> -w
   ```

The steps above restore the **latest** backup — the app's `Restore` object (from the `kopiur-backup` component) defaults to `spec.source.fromPolicy.offset: 0`. This isn't yet exposed as an easy override in the shared component, so restoring to a specific older backup means patching the `Restore` object directly, before step 4 (deleting the PVC):

```sh
# find the Snapshot to restore -- reuse "list all available backups" above
❯ kubectl get snapshot -n <namespace> -l kopiur.home-operations.com/config=<app>

# point the Restore at that exact Snapshot CR (clears fromPolicy, sets snapshotRef)
❯ kubectl patch restore <app> -n <namespace> --type merge \
    -p '{"spec":{"source":{"fromPolicy":null,"snapshotRef":{"name":"<snapshot-name>"}}}}'
```

Two other selectors work too, if a specific `Snapshot` CR isn't handy:
- `fromPolicy.offset: N` — the Nth-from-latest snapshot in this policy's succession (`0` = latest, `1` = previous, ...).
- `fromPolicy.asOf: "<RFC3339 timestamp>"` — the newest snapshot at or before that point in time.

After the restore, revert the `Restore` object back to its default (latest) so a future *accidental* PVC loss doesn't silently restore from this now-stale pin:

```sh
❯ kubectl patch restore <app> -n <namespace> --type merge \
    -p '{"spec":{"source":{"snapshotRef":null,"fromPolicy":{"name":"<app>","offset":0}}}}'
```

### Prune old backups

Retention is automatic and GFS-based (see above) — normal operation needs no manual pruning. kopiur has no built-in "delete everything older than N days" command; if you need one anyway (e.g. after changing retention settings, or cleaning up a since-deleted test app's history), delete the matching `Snapshot` CRs directly:

Relative — everything older than N days:

```sh
# macOS/BSD date; on Linux use: date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ
❯ CUTOFF=$(date -u -v-30d +%Y-%m-%dT%H:%M:%SZ)
❯ kubectl get snapshot -n <namespace> -l kopiur.home-operations.com/config=<app> -o json \
    | jq -r --arg cutoff "$CUTOFF" '.items[] | select(.metadata.creationTimestamp < $cutoff) | .metadata.name' \
    | xargs -r -n1 kubectl delete snapshot -n <namespace>
```

Absolute — everything before a specific date (e.g. cleaning up everything from before a known-bad period):

```sh
❯ CUTOFF="2026-08-01T00:00:00Z"
❯ kubectl get snapshot -n <namespace> -l kopiur.home-operations.com/config=<app> -o json \
    | jq -r --arg cutoff "$CUTOFF" '.items[] | select(.metadata.creationTimestamp < $cutoff) | .metadata.name' \
    | xargs -r -n1 kubectl delete snapshot -n <namespace>
```

Deleting a `Snapshot` CR (`deletionPolicy: Delete`, the default for produced backups) also deletes the underlying kopia snapshot from the repository, not just the Kubernetes object.

## Storage classes involved

| Class | Role |
|---|---|
| `longhorn-standard` | Default class for an app's actual data (`KOPIUR_STORAGECLASS`) |
| `longhorn-snapshot` | `VolumeSnapshotClass` used to capture the source PVC |
| `longhorn-scratch-ext4` / `longhorn-scratch-xfs` | Fast, disposable staging PVC for the mover (`KOPIUR_STAGING_STORAGECLASS`) — must match the source's fsType, or the mover fails at mount time ("wrong fs type, bad superblock") |

## Automatic per-env credentials

Each environment has its own bucket and credentials (`kopiur-backup#dev`, `kopiur-backup#qa`, etc.). The `kopiur-secret-env` transformer (`k8s/components/transformers/kopiur-secret-env`, included by every `k8s/components/envs/<env>`) rewrites `kopiur-secret`'s `ExternalSecret` key accordingly (`kopiur-backup#base` → `kopiur-backup#dev`, ...) — no per-app patching needed, and it's a no-op for apps that don't include `kopiur-backup` at all.

## Known caveats

- **fsType matching**: the staging `StorageClass` must match the source data's filesystem — a `VolumeSnapshot` restore is a raw block-level copy, not a reformat. Documented inline in `k8s/components/apps/kopiur/backup/snapshotpolicy.yaml`.
