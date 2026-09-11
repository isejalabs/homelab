# Kopiur Backup & Restore

## Overview

[kopiur](https://github.com/home-operations/kopiur) is the Kubernetes-native backup operator used in this cluster. It snapshots PVC data via CSI `VolumeSnapshot`s, uploads it with [kopia](https://kopia.io) (a content-addressable, deduplicating backup engine) to an S3-compatible repository, and can populate new PVCs from those backups via the standard Kubernetes CSI PVC-populator mechanism.

- **Repository**: `fiona`, a `ClusterRepository` pointing at this cluster's S3-compatible NAS (`fiona.home.iseja.net:9000`), with a separate bucket per environment (`<env>-kopiur-backup`) in all 8 environments.
- **Wiring an app up**: include exactly one of `apps/storage/pvc` or `apps/storage/pvc-no-backup` in the app's `base/kustomization.yaml` -- requiring storage gets it backed up automatically by default; use `pvc-no-backup` only when the data genuinely doesn't need protecting. Both pull in kopiur's credential-wiring `apps/kopiur/secret` component automatically -- no separate reference needed, and no per-env patching either (see [Automatic per-env credentials](#automatic-per-env-credentials) below). See [k8s/components/apps/storage/README.md](../k8s/components/apps/storage/README.md) for what each component does, and [docs/app-storage.md](app-storage.md) for the full variable/storage-class reference.
- **Two independent backup layers exist.** Longhorn's own native `RecurringJob`s (`k8s/infra/longhorn-system/longhorn/base/job-*.yaml`) already give *every* Longhorn volume an hourly local snapshot plus daily/weekly/monthly offsite backups automatically (the latter only in `dev`/`qa`/`rebuild`/`prod`), with zero per-app setup. kopiur adds a second, independent offsite layer on top, for apps explicitly opted in via `apps/storage/pvc`. Once an app is on kopiur, it's covered by both -- deliberate defense-in-depth (the two fail independently, via entirely different backend integrations) rather than redundant waste, even though both now run on a similar (daily) cadence.
- **Not every environment runs an active schedule.** `dbg`/`head`/`poc`/`src` get a real bucket and the storage components too (so `Restore`'s CSI populator has something valid to connect to), but any `SnapshotSchedule` there is force-suspended by the `suspend-kopiur-schedule` transformer -- see [Dormant environments](#dormant-environments) below.

## How it works

### Restore-on-create: the core idea

An app's PVC has `dataSourceRef` pointing at a `Restore` object, using the CSI PVC-populator mechanism. This one mechanism covers both of the cases that matter, adapted from [onedr0p/home-ops](https://github.com/onedr0p/home-ops)' original design (see [Credits & changes from upstream](#credits--changes-from-upstream)):

- **An existing backup exists** (app redeployed, PVC deleted/recreated, or a full namespace recreation): kopiur automatically restores the latest matching snapshot into the new PVC *before* any pod can mount it -- kubelet just waits. No explicit "restore" command needed for the common "the volume got lost and needs to come back" case.
- **No backup exists yet** (very first deploy): `Restore.spec.policy.onMissingSnapshot: Continue` populates an empty volume instead of blocking forever. Confirmed live: a brand-new app's PVC binds and its pod starts immediately, no manual intervention needed.

### Ongoing protection (`apps/storage/pvc` only)

A `SnapshotSchedule` fires daily (`cron: H 3 * * *`, off-peak, ahead of Longhorn's own ~4am jobs) per app, creating a `Snapshot` object. That `Snapshot`:
1. Takes a CSI `VolumeSnapshot` of the source PVC.
2. Restores it into a temporary staging PVC (`longhorn-scratch-ext4`/`longhorn-scratch-xfs` -- fast, single-replica, disposable; **must match the source PVC's filesystem**, since a `VolumeSnapshot` restore is a raw block copy, not a reformat -- see [docs/app-storage.md](app-storage.md)).
3. Runs the kopia mover, which reads the staging PVC and uploads to `fiona`.
4. Deletes the staging PVC automatically once done (confirmed: no accumulation from routine operation, only from the app itself being deleted/recreated repeatedly, which orphans the *data* PVC's old `Retain`-policy volume, not the staging one).

Retention is GFS-style (`SnapshotPolicy.spec.retention`: `keepLatest` / `keepHourly` / `keepDaily` / `keepWeekly`) -- old snapshots beyond those counts are pruned automatically; no manual cleanup needed for normal operation. `keepHourly` is `0` now that snapshots are daily, not hourly.

### Dormant environments

`dbg`/`head`/`poc`/`src` are throwaway/ephemeral environments that don't need scheduled protection, but should still have storage provisioning behave consistently with the rest of the cluster. Rather than excluding them from the storage components entirely, the [`suspend-kopiur-schedule`](../k8s/components/transformers/suspend-kopiur-schedule) transformer (registered only in those 4 envs' `k8s/components/envs/<env>/kustomization.yaml`) force-patches every `SnapshotSchedule` to `spec.schedule.suspend: true`, regardless of which storage component an app picked. The object stays visible (`kubectl get snapshotschedule` shows `Suspended: true`) rather than disappearing -- "available, not activated," not excluded.

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

The steps above restore the **latest** backup — the app's `Restore` object (from the `apps/storage/pvc`/`pvc-no-backup` components) defaults to `spec.source.fromPolicy.offset: 0`. This isn't yet exposed as an easy override in the shared component, so restoring to a specific older backup means patching the `Restore` object directly, before step 4 (deleting the PVC):

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

## Automatic per-env credentials

Each environment has its own bucket and credentials (`kopiur-backup#dev`, `kopiur-backup#qa`, etc.), for all 8 environments. The `kopiur-secret-env` transformer (`k8s/components/transformers/kopiur-secret-env`, included by every `k8s/components/envs/<env>`) rewrites `kopiur-secret`'s `ExternalSecret` key accordingly (`kopiur-backup#base` → `kopiur-backup#dev`, ...) and the `ClusterRepository`'s bucket name the same way — no per-app patching needed, and it's a no-op for apps that don't include `apps/storage/pvc`/`pvc-no-backup` at all.

## Known caveats

- **fsType matching**: the staging `StorageClass` must match the source data's filesystem — a `VolumeSnapshot` restore is a raw block-level copy, not a reformat. Full variable reference and the storage-class table live in [docs/app-storage.md](app-storage.md); the rule itself is documented inline in `k8s/components/apps/storage/pvc-no-backup/snapshotpolicy.yaml`.

## Credits & changes from upstream

This is adapted from [onedr0p/home-ops](https://github.com/onedr0p/home-ops)' original kopiur backup component -- including the core "existing backup restores automatically on fresh bootstrap, otherwise a clean PVC" idea described above, which is onedr0p's design, not this repo's. Changes made since adopting it:

- Storage classes: Ceph-specific defaults (`csi-ceph-blockpool`, `ceph-block`, `miroir-slow`) replaced with this cluster's Longhorn equivalents.
- Coverage extended to all 8 environments, with `dbg`/`head`/`poc`/`src` dormant (see [Dormant environments](#dormant-environments)) rather than excluded outright.
- Off-site cadence changed from hourly to daily (`H 3 * * *`), since Longhorn's own hourly *local* snapshots already cover the "recent changes" recovery case independently.
- The single `kopiur-backup` component was split into an opt-*out* pair, `apps/storage/pvc` (default, includes backup) and `apps/storage/pvc-no-backup` (explicit exception) -- see [k8s/components/apps/storage/README.md](../k8s/components/apps/storage/README.md).
- App-facing variables (`KOPIUR_*`) renamed to generic, implementation-agnostic names (`STORAGE_*`, `PUID`/`PGID`) so the interface doesn't hard-depend on kopiur specifically -- see [docs/app-storage.md](app-storage.md).
