## Purpose

Shared kustomize `Component`s for provisioning an app's PVC. An app needing storage includes exactly one
of these in its `base/kustomization.yaml` — requiring a PVC gets it backed up automatically, by default.

- **`pvc/`** (the default) — `PVC` + `Restore` + `SnapshotPolicy` + `SnapshotSchedule`. Everything needed
  for an app's data volume to be automatically backed up daily to the `fiona` `ClusterRepository`, and to
  be restorable via the CSI populator mechanism when its PVC is (re)created.
- **`pvc-no-backup/`** — the explicit exception: `PVC` + `Restore` + `SnapshotPolicy`, no `SnapshotSchedule`.
  For storage that genuinely doesn't need protecting (e.g. ephemeral/regenerable data), but still needs
  real, reschedulable storage rather than node-local disk. `pvc/` is built on top of this (adds the
  schedule) rather than the other way round — `pvc-no-backup/`'s files are the canonical copy.

Both depend on [`apps/kopiur/secret`](../kopiur/secret) automatically — no separate reference needed. In
environments where kopiur backup isn't actively scheduled (`dbg`/`head`/`poc`/`src` as of this writing),
any `SnapshotSchedule` an app creates via `pvc/` is force-suspended by the
[`suspend-kopiur-schedule`](../../transformers/suspend-kopiur-schedule) transformer, registered per-env —
this overrides whichever component an app picked, as a guardrail.

Per-env credentials (`kopiur-secret`'s `dataFrom.extract.key`) are rewritten automatically by the
`kopiur-secret-env` transformer — no per-app patching needed. See
[docs/app-storage.md](../../../../docs/app-storage.md) for the full `STORAGE_*`/`PUID`/`PGID` variable
reference and the storage-class/filesystem pairing rules, and
[docs/kopiur-backup-restore.md](../../../../docs/kopiur-backup-restore.md) for how the backup/restore
mechanism itself works.

## Wiring up an app

Two files change. `${APP}` is a placeholder throughout `pvc`/`pvc-no-backup` (it's what makes the
component reusable across apps) — it must be set alongside any `STORAGE_*` override, or the PVC/Restore/
policy/schedule objects will literally be named `${APP}` instead of your app's name.

**1. `base/kustomization.yaml`** — add the component (`pvc` for the default, backed-up case; swap in
`pvc-no-backup` for the opt-out case). Following the [field-ordering convention](../../../../.agents/instructions/sorting.md), `components` goes before `resources`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: myapp

components:
  - ../../../../components/apps/storage/pvc # or pvc-no-backup

resources:
  - deployment.yaml
  - service.yaml
```

(Path depth depends on where your app lives — `../../../../components/apps/storage/pvc` is correct for
the common `k8s/apps/<domain>/<app>/base/` layout; adjust the `../` count if your app sits elsewhere.)

**2. `flux/ks.yaml`** — set `APP` via `postBuild.substitute`, plus any `STORAGE_*`/`PUID`/`PGID` override
your app needs (see [docs/app-storage.md](../../../../docs/app-storage.md) for the full list and defaults
— most apps only need `APP`, everything else has a sensible default):

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: myapp
spec:
  interval: 1h
  path: ./k8s/apps/<domain>/myapp/base
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  wait: true
  postBuild:
    substitute:
      APP: myapp
      # STORAGE_CAPACITY: 10Gi
      # STORAGE_CLASS: longhorn-xfs           # if this app needs xfs
      # STORAGE_STAGING_CLASS: longhorn-scratch-xfs  # required alongside an xfs STORAGE_CLASS
      # PUID: "1001"
      # PGID: "1001"
```

That's it — no per-env patching, no separate secret wiring. The app's PVC binds empty on first deploy
(`onMissingSnapshot: Continue`), and from then on (if using `pvc`, not `pvc-no-backup`) is backed up daily
per [docs/kopiur-backup-restore.md](../../../../docs/kopiur-backup-restore.md).
