# Storage: Longhorn vs. proxmox-csi

Two storage backends are available in-cluster. This isn't a permanent 50/50 split: **Longhorn is replacing
proxmox-csi step by step**, and proxmox-csi is being kept only where there's a specific benefit to sticking
with Proxmox-provided volumes instead — chiefly, surviving a full cluster teardown/rebuild without depending
on Longhorn's own backup/restore path. So the practical question for a new volume isn't "which is better" but
"does this volume need the proxmox-csi property badly enough to justify it" — if not, it goes on Longhorn.
That consolidation is also what's driving [issue #807](https://github.com/isejalabs/homelab/issues/807),
currently being worked on, to give the cluster consistent, reliable storage provisioning and backup/restore
in one place, rather than the two different lifecycle stories this doc otherwise has to describe.

## proxmox-csi — Terragrunt-pinned volumes that survive a cluster rebuild

[`k8s/infra/csi-proxmox/`](../../k8s/infra/csi-proxmox/) installs the
[`sergelogvinov/proxmox-csi-plugin`](https://github.com/sergelogvinov/proxmox-csi-plugin) driver via Flux —
it's part of the **minimal** infra set (`k8s/bootstrap/cluster/flux/sets/infra/minimal/`), so every
environment gets it regardless of which apps it runs. Its one StorageClass
([`k8s/infra/csi-proxmox/proxmox-csi/base/helmrelease.yaml`](../../k8s/infra/csi-proxmox/proxmox-csi/base/helmrelease.yaml)):

```yaml
values:
  storageClass:
    - name: proxmox-csi
      cache: writethrough
      fstype: ext4
      reclaimPolicy: Retain
      ssd: true
      storage: local-enc # the Proxmox storage pool backing these disks
      mountOptions:
        - noatime
```

The CSI driver itself only needs a namespace and a Proxmox API credential to talk to the hypervisor — those
two prerequisites are provisioned by **Terragrunt**, not Flux/bootstrap, confirmed by the
[`terragrunt/README.md`](../../terragrunt/README.md) "Delete dangling states" list:
`module.proxmox_csi_plugin.kubernetes_secret.proxmox-csi-plugin` and
`module.proxmox_csi_plugin.kubernetes_namespace.csi-proxmox`. So proxmox-csi is a joint effort: Terragrunt
lays the groundwork (namespace, credentials), Flux installs and runs the driver on top of it.

### The actual volumes: pinned, not dynamic

Every real proxmox-csi PVC in this repo binds to a **specific, pre-existing** `PersistentVolume` by name
instead of letting the StorageClass dynamically provision one — e.g.
[`k8s/apps/network/unifi-controller/base/pvc-db.yaml`](../../k8s/apps/network/unifi-controller/base/pvc-db.yaml):

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mongodb-data
spec:
  storageClassName: proxmox-csi
  volumeName: pv-mongodb # statically bound, not dynamically provisioned
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 800M
```

That `pv-mongodb` `PersistentVolume`, and the actual Proxmox-side disk backing it, are declared in
Terragrunt — [`terragrunt/_envcommon/vehagn-k8s.hcl`](../../terragrunt/_envcommon/vehagn-k8s.hcl):

```hcl
# volumes
pv-mongodb_size = "1024M"
pv-unifi_size   = "500M"
```

and applied by a `volumes` module with two paired sub-modules per named volume, confirmed by
`terragrunt/README.md`'s recovery-import example:

```sh
terragrunt import 'module.volumes.module.proxmox-volume["pv-mongodb"].restapi_object.proxmox-volume' /api2/json/nodes/pve4/storage/local-enc/content/local-enc:vm-9813-dev-pv-mongodb
terragrunt import 'module.volumes.module.persistent-volume["pv-mongodb"].kubernetes_persistent_volume.pv' pv-mongodb
```

`module.volumes.module.proxmox-volume[...]` is the actual disk on the Proxmox hypervisor;
`module.volumes.module.persistent-volume[...]` is the matching Kubernetes `PersistentVolume` object. Both are
indexed by volume name (`pv-mongodb`, `pv-unifi`), and both are managed by an external Terraform module (not
vendored into this repo, referenced only by URL from `vehagn-k8s.hcl`'s `base_source_url`).

**Surviving a cluster rebuild** is the entire point of routing a volume through Terragrunt instead of
Longhorn. Before destroying a cluster, its Proxmox-side disk state is deliberately stripped out of Terraform
state so `terragrunt destroy` never touches the real disk —
[`terragrunt/README.md`](../../terragrunt/README.md#prevent-deletion-of-proxmox-volumes):

```sh
for i in $(terragrunt state list | grep module.volumes.module.proxmox-volume); do terragrunt state rm "$i"; done
```

([`scripts/tg-state-rm.sh`](../../scripts/tg-state-rm.sh) automates this, alongside removing other dangling
state — the k8s-side `persistent-volume` entries, `sealed_secrets`, `talos.*`, and the proxmox-csi
namespace/secret — so a destroy doesn't hang or fail on stale references;
[`scripts/volume-remove-state.sh`](../../scripts/volume-remove-state.sh) does the narrower proxmox-volume-only
version, with the comment *"allows re-using them upon re-creating the cluster (needs state import then)"*.)
The disk (and its data — MongoDB's data directory, in the unifi-controller example) physically survives the
teardown. On rebuild, [`terragrunt/README.md`](../../terragrunt/README.md#import-proxmox-volume)'s import
commands above re-attach the surviving Proxmox disk plus a fresh `PersistentVolume` object to the new
cluster.

## Longhorn — ordinary in-cluster dynamic storage

[`k8s/infra/longhorn-system/`](../../k8s/infra/longhorn-system/) is split into two Flux `Kustomization`s in
the **optional** infra set (`k8s/bootstrap/cluster/flux/sets/infra/optional/`) — so unlike proxmox-csi, it's
only present where an environment's Flux set actually includes it:

- `longhorn-core` installs the Helm chart itself
  ([`base/helmrelease.yaml`](../../k8s/infra/longhorn-system/longhorn-core/base/helmrelease.yaml)):
  chart `v1.12.1`, `defaultSettings.defaultDataPath: /var/mnt/longhorn`, `defaultReplicaCount: 2`, and a
  deliberately small footprint (`longhornUI.replicas: 1`, single-replica CSI sidecars) appropriate for a
  homelab rather than a large production fleet.
- `longhorn` (`dependsOn: longhorn-core`) carries the custom `StorageClass`es, a `VolumeSnapshotClass`, and
  backup/trim/snapshot `RecurringJob`s.

### StorageClasses — one driver, several tradeoff profiles

There are six, not five — one easy to miss because it isn't declared alongside the others. Five are custom,
in [`k8s/infra/longhorn-system/longhorn/base/sc-*.yaml`](../../k8s/infra/longhorn-system/longhorn/base/),
sharing `provisioner: driver.longhorn.io`, `reclaimPolicy: Retain`, `volumeBindingMode: WaitForFirstConsumer`,
`allowVolumeExpansion: true` — only the `parameters:` differ:

| StorageClass | fsType | replicas | notes |
| --- | --- | --- | --- |
| `longhorn-standard` | ext4 | 2 | general-purpose |
| `longhorn-ext4` | ext4 | 2 | same profile, explicit ext4 |
| `longhorn-xfs` | xfs | 2 | same profile, xfs |
| `longhorn-fast` | xfs | 1 | `dataLocality: strict-local`, revision counter disabled — trades HA/consistency for speed |
| `longhorn-ha` | xfs | 3 | zone/node soft anti-affinity, `replicaAutoBalance: best-effort` — max resilience |

The sixth, **`longhorn`**, is not defined in that `base/` folder at all — it's created automatically by the
Longhorn Helm chart itself (`longhorn-core`'s
[`base/helmrelease.yaml`](../../k8s/infra/longhorn-system/longhorn-core/base/helmrelease.yaml)):

```yaml
persistence:
  # -- Replica count of the default Longhorn StorageClass.
  defaultClassReplicaCount: 1
```

The chart's own default (`persistence.defaultClass: true`, not overridden here) both creates this
`longhorn` class and marks it `storageclass.kubernetes.io/is-default-class: "true"` — **`longhorn` is the
cluster's actual default StorageClass**, with a replica count of 1. None of the five custom classes above
override that default themselves — [`sc-standard.yaml`](../../k8s/infra/longhorn-system/longhorn/base/sc-standard.yaml)
explicitly sets its own annotation to `storageclass.kubernetes.io/is-default-class: "false"` despite the
name "standard" inviting the assumption it's the default — so a PVC that names no `storageClassName` at all
lands on `longhorn` (replica count 1), not on `longhorn-standard` (replica count 2). Real usage example, one
of the five *named* classes (not the implicit default), from
[`k8s/apps/finances/actualbudget/base/helmrelease.yaml`](../../k8s/apps/finances/actualbudget/base/helmrelease.yaml):

```yaml
persistence:
  size: 1Gi
  storageClass: longhorn-standard
```

That's a genuinely dynamic PVC — no pre-created `PersistentVolume`, no Terragrunt involvement, just a
StorageClass reference. This is the default pattern for any app that needs a volume: pick the
`longhorn-*` class matching its consistency/performance needs, and let Longhorn provision and replicate it.
Longhorn's own S3-backed `RecurringJob`s
([`job-backup-default.yaml`](../../k8s/infra/longhorn-system/longhorn/base/job-backup-default.yaml)) are the
backup mechanism for this tier today — there's no Terragrunt-style state-exclusion/re-import dance for
Longhorn volumes, so they don't automatically survive a full cluster rebuild the way proxmox-csi's pinned
volumes do. [Issue #807](https://github.com/isejalabs/homelab/issues/807) is the tracked effort to make this
more rigorous: it settled on [kopiur](https://github.com/home-operations/kopiur) over
[VolSync](https://github.com/backube/volsync) as the backup/restore operator, split into the Kubernetes-side
rollout ([#1127](https://github.com/isejalabs/homelab/issues/1127) — operator, components, StorageClasses),
the S3 backup target in RustFS ([#1128](https://github.com/isejalabs/homelab/issues/1128)), and the
1Password credentials kopiur needs to authenticate against it
([#1129](https://github.com/isejalabs/homelab/issues/1129)).

## Choosing between them

Longhorn is the default going forward — proxmox-csi is being phased out for new workloads, kept only where
its specific properties are worth the Terragrunt overhead:

- **proxmox-csi** — reach for it only when a volume needs to survive a full cluster teardown/rebuild by
  Terragrunt import rather than Longhorn's own backup/restore, or when its size/placement is meaningful
  enough to want declared explicitly in Terragrunt. In practice: the handful of volumes an app absolutely
  cannot lose (e.g. unifi-controller's MongoDB data) that predate the move to Longhorn.
- **Longhorn** — the default for everything else, and increasingly for workloads that used to be
  proxmox-csi candidates too. Ordinary app storage, provisioned on demand, replicated for HA at the storage
  layer instead of the infrastructure layer, with its own backup mechanism if durability across a rebuild
  matters.

## `reclaimPolicy: Retain` and the two-step cleanup gotcha

Both backends use `reclaimPolicy: Retain` everywhere, deliberately: deleting a `PersistentVolumeClaim` (or
its namespace) never deletes the underlying volume automatically, trading a bit of manual cleanup for
protection against accidental data loss. This matters most when spinning up throwaway test resources — e.g.
via the [`track-branch`](../../.agents/skills/track-branch/SKILL.md) skill on a non-`prod` environment — and
is called out explicitly in [`../../CLAUDE.md`](../../CLAUDE.md):

> Clean up any test-created resources afterward, including Retain-policy PVs/Longhorn volumes, which outlive
> the PVC/namespace that claimed them and need deleting both as the k8s `PersistentVolume` object and the
> underlying `volumes.longhorn.io` object.

For Longhorn specifically that's a **two-object** cleanup — the k8s `PersistentVolume` and the
`volumes.longhorn.io` custom resource underneath it both need deleting, or the disk space and the Longhorn
volume record both leak. proxmox-csi volumes leak the same way at the k8s `PersistentVolume` level, but
because real proxmox-csi volumes in this repo are Terragrunt-declared rather than ad hoc, the equivalent
cleanup for them is the `terragrunt state rm`/destroy flow described above, not a manual `kubectl delete`.
