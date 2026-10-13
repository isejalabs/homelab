---
status: current
---

# Node lifecycle: Talos/Kubernetes upgrades and node replacement

How to move one environment from one pinned Talos/Kubernetes version to another, replace a single node, scale a node count up or down, or relocate a node to a different Proxmox host — all in an otherwise-healthy cluster. Not a full cluster rebuild — see [`disaster-recovery.md`](disaster-recovery.md) for that, and [`architecture/environments.md`](architecture/environments.md) for what each environment is and why `prod` gets stricter rules (`main`-checkout-only applies, no `track-branch` override) than the others.

Every node is provisioned by Terragrunt/the `terraform-proxmox-talos` module (see [ADR 0001](decisions/0001-proxmox-and-talos.md)), which has one real consequence for both procedures here: **neither Talos itself nor Kubernetes is upgraded in place the way the upstream tools' own docs describe** — `terraform-provider-talos` doesn't support in-place Talos upgrades at all ([siderolabs/terraform-provider-talos#140](https://redirect.github.com/siderolabs/terraform-provider-talos/issues/140)), and this repo hasn't adopted [tuppr](https://github.com/home-operations/tuppr) yet either (see ADR 0001's Open decisions). What follows is the module's own documented workaround — see the module's [Upgrade Methods](https://github.com/isejalabs/terraform-proxmox-talos/blob/main/docs/upgrade%20methods.md) doc for the full, authoritative version (schematic upgrades, VM config changes, module version upgrades, and Cilium/Gateway API/proxmox-csi component upgrades are all covered there too, out of scope for this doc).

## 1. Talos OS upgrade

A Talos version bump isn't applied in place — each node's `terraform-proxmox-talos` module config has a per-node `update` flag (`optional(bool, false)`); flipping it to `true` and applying makes that node's VM boot from a newly-downloaded image at the new version, which **destroys and recreates the Talos VM** for that node. A separate "data VM" (holding `EPHEMERAL` and other data disks) is untouched by this, so node-local data survives — conceptually the same guarantee as `talosctl upgrade --preserve=true`, achieved a different way because the provider can't do an in-place upgrade at all.

Every environment's `vehagn-k8s/terragrunt.hcl` already has this flag present-but-commented on every node (e.g. [`terragrunt/non-prod/eu-central-1/dev/vehagn-k8s/terragrunt.hcl`](../terragrunt/non-prod/eu-central-1/dev/vehagn-k8s/terragrunt.hcl)):

```hcl
"${local.env}-work-01.${local.domain}" = {
  ...
  # update        = true
}
```

**Upgrade control-plane nodes first, then workers** — this keeps the control plane on the newer, more capable version throughout. One node at a time:

1. Set `image.update_version` (in the environment's `terragrunt.hcl` `cluster`/`image` block) to the target Talos version.
2. **Taint the node before touching Terragrunt** — flipping `update = true` and applying destroys and recreates the VM via Terraform's own `stop_on_destroy`, a hard stop with no graceful Kubernetes-level awareness, the same gap documented in [Node replacement](#3-node-replacement) below. Cordon and drain first so existing pods reschedule onto other nodes cleanly (respecting PodDisruptionBudgets) instead of being killed outright when the VM disappears:

   ```sh
   kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
   ```

   `kubectl cordon` (which `drain` does first, automatically) is literally a taint under the hood (`node.kubernetes.io/unschedulable:NoSchedule`) — this is the same mechanism, not a separate step to remember.

   **`drain` still evicts immediately, leaving a brief gap** until the evicted pod's replacement is scheduled and `Ready` elsewhere — it doesn't wait for a replacement to come up first. The real way to avoid that gap for a workload that can tolerate it: cordon the node (no eviction yet), then `kubectl rollout restart deployment/<name> -n <namespace>` so the Deployment's own `maxSurge` creates a replacement pod on a schedulable node *before* the old one is touched, wait for `kubectl rollout status deployment/<name> -n <namespace>` to confirm it's `Ready`, and only then remove the old pod (`drain` at that point is a fast no-op for that workload, since it's already moved). This needs a second replica to surge to and a storage class that can be mounted from two nodes at once — **neither holds for any workload in this repo today**: every `Deployment` here runs `replicas: 1` (`whoami`, `adguard`, `unifi-controller`, `unifi-mongodb`, even Longhorn's own manager), and the default PVC access mode is `ReadWriteOnce` (see [`app-storage.md`](app-storage.md)), so a second pod couldn't mount the same volume on another node even temporarily. With exactly one instance, moving it means stopping it here and starting it there — a real, if brief, gap that can be minimized (fast image pull, quick readiness probe) but not scheduled away. Accepted as-is for this homelab; revisit only if a workload here ever genuinely needs multiple replicas.

   For a **control-plane node** specifically, also have it leave `etcd` cleanly before its VM is destroyed:

   ```sh
   talosctl --nodes <node-ip> etcd leave
   ```
3. Uncomment `update = true` on the node's entry, run `terragrunt apply`, confirm the node rejoins healthy (`flux get ks -A`/`flux get hr -A` — see [`troubleshooting-flux.md`](troubleshooting-flux.md) if anything looks stuck) before moving on — the replacement VM comes back schedulable by default, no need to manually uncordon it.
4. **If that node carried any Longhorn replicas, check every affected volume's robustness before touching the next node** (`kubectl get volumes.longhorn.io -n longhorn-system`, same command as [`troubleshooting-storage.md`](troubleshooting-storage.md#2-a-longhorn-volume-degraded-or-faulted)):
   - A **single-replica** volume (`longhorn-fast`, or the cluster's implicit `longhorn` default) has no redundancy to begin with — it going briefly unavailable while that one node's VM is destroyed and recreated is expected, not a blocker.
   - A **multi-replica** volume (`longhorn-standard`/`-ext4`/`-xfs`, `longhorn-ha`) must be back to `ROBUSTNESS: Healthy` — not just `Degraded` — before taking down the *next* node. Moving on while still `Degraded` risks that next node holding another one of the same volume's replicas, which would drop it to zero healthy copies.
   - This isn't about Longhorn's own replica/engine *version* drifting — that's a container image pulled by the Longhorn manager, decoupled from the node's Talos/kernel version, so a Talos upgrade can't cause it to skew between replicas. The actual risk this check guards against is replica *data* going out of sync (a rebuild in progress) while another one of the volume's copies is taken down too — i.e. the ordinary meaning of "wait for `Healthy` before touching the next node," not a version-compatibility concern.
5. Repeat from step 2 for the next node — **leave the previous node(s)' `update = true` in place**, don't revert them in between.
6. Once every node in the environment is on the new version: set `image.version` to match `image.update_version`, remove `image.update_version`, and reset every node's `update` back to `false`/commented-out, then `terragrunt apply` once more. This is the step that actually makes the new version the environment's steady-state baseline rather than a lingering per-node override.

Multiple nodes *can* be flipped and applied together to go faster, but always leave at least one control-plane node and enough workers untouched to keep the cluster serving traffic during the change — per the module's own guidance, don't apply the same change to every node of a kind at once.

**A Talos OS upgrade does not upgrade Kubernetes** — the two are deliberately decoupled (see below). Don't set `cluster.kubernetes_version` as part of this step.

## 2. Kubernetes version upgrade

Separate from the Talos OS version, and recommended after every Talos OS upgrade to keep the two aligned (check the [Talos/Kubernetes support matrix](https://docs.siderolabs.com/talos/v1.12/getting-started/support-matrix) first — not every Talos version supports every Kubernetes version). There's no per-node `update` flag for this one; a hybrid imperative-then-declarative approach is used instead, so the rollout is a real rolling upgrade rather than every node upgrading its Kubernetes components in parallel (which would make the control plane briefly unresponsive):

1. Get talosconfig access if you don't already have it (see [`terragrunt/README.md#talosconfig`](../terragrunt/README.md#talosconfig)), then run the rolling upgrade itself from any control-plane node:

   ```sh
   talosctl --nodes <control-plane-ip> upgrade-k8s --to <new-k8s-version>
   ```

   This upgrades one node at a time automatically (control plane first) and pre-pulls `kubelet`/`kube-apiserver`/`kube-scheduler`/`etcd` images on each node before switching, minimizing downtime.

2. Once that completes, set `cluster.kubernetes_version` to the same version in the environment's `terragrunt.hcl` and run `terragrunt apply` — this reconciles Terraform's own state with what `talosctl` just did, so a later unrelated `terragrunt apply` doesn't try to "correct" the version back.

## 3. Node replacement

For replacing one node (hardware failure, moving to a different Proxmox host) while the rest of the cluster stays healthy — not for a full environment rebuild.

1. **Drain and gracefully remove the departing node first**, before touching Terragrunt — Terraform's own destroy is just a hard Proxmox-level VM stop (`stop_on_destroy = true` in the module, not a graceful Talos/Kubernetes shutdown), so skipping this step risks a stuck `etcd` member (control-plane node) or pods killed without a clean drain:

   ```sh
   talosctl reset --nodes <node-ip> --graceful --reboot
   ```

   A graceful reset cordons the node in Kubernetes, drains its workloads, and — for a control-plane node — leaves the `etcd` cluster cleanly, before wiping and shutting down. Same eviction-gap caveat as [Talos OS upgrade](#1-talos-os-upgrade) above applies here too — this drains immediately rather than waiting for a replacement elsewhere. Confirm a control-plane node actually left `etcd` before proceeding:

   ```sh
   talosctl --nodes <any-remaining-control-plane-ip> etcd members
   ```

2. **Edit the environment's `terragrunt.hcl`** `nodes` map: remove the departing node's entry (or update its `host_node`/`ip`/`vm_id` in place if it's staying at the same logical slot but moving to different physical hardware), then add the replacement's entry. Reuse the same map key and `vm_id` for a straight swap in the same slot; pick an unused `vm_id` from the environment's own `70081<id><n>` range (see [`reference/environments.md#environment-id`](reference/environments.md#environment-id)) if adding a genuinely new slot instead.
3. `terragrunt apply` — this provisions the new VM, installs Talos, and the node joins the cluster automatically. No manual Cilium BGP configuration is needed: `CiliumBGPClusterConfig` selects peers by node label/role, not by a static per-node list (see [ADR 0008](decisions/0008-cilium-bgp.md)), so a new node matching the existing `nodeSelector` peers automatically once it's up.
4. **If `terragrunt apply` errors on `cluster health check failed` / `unexpected nodes with IPs [...]` even though the destroy itself clearly succeeded** (confirmed live, 2026-10-11): the departed node's VM is gone from Proxmox, but its Kubernetes `Node` object doesn't get removed automatically just because the underlying machine did — the module's own post-apply `talos_cluster_health` check fails on that stale, unreachable peer. Confirm with `kubectl get nodes` (the departed node shows `NotReady`), delete it (`kubectl delete node <name>`), then re-run `terragrunt apply` — it converges cleanly (`0 added, 0 changed, 0 destroyed`) once the stale object is gone. This isn't a sign the node removal failed; the infrastructure change already took, this is purely the health check being pickier than a plain destroy.
5. **Clean up Longhorn's record of the departed node**, if it ran any Longhorn replicas — Longhorn doesn't always remove its own `nodes.longhorn.io` object just because the underlying Kubernetes `Node` is gone, and a replacement node comes up with a **new, empty Longhorn disk**: Longhorn then reports `DiskFilesystemChanged` for it and does not use it. Replicas that lived on the old disk are gone; Longhorn rebuilds them onto *other* nodes only while it has a schedulable node left for each. Follow [Longhorn disk of a replaced or moved worker](#longhorn-disk-of-a-replaced-or-moved-worker) below, and confirm `ROBUSTNESS: Healthy` before considering the replacement done (see [`troubleshooting-storage.md`](troubleshooting-storage.md#2-a-longhorn-volume-degraded-or-faulted) for checking replica health).

## 4. Ramping control-plane/worker node count up or down

Temporarily or permanently changing how many nodes an environment runs — e.g. adding a second control-plane node for a bit of HA headroom during other maintenance, or scaling workers up for a one-off capacity need. This is the module's general-purpose "cluster scaling" mechanism (adding/removing entries from the `nodes` map); node replacement (above) and moving a node to another host (below) both build directly on it.

- **Ramp up**: uncomment or add a node entry (any unused slot in the environment's `70081<id><n>` range) and `terragrunt apply`. For a **control-plane** node specifically, the module's own `talos_cluster_health` check gates the apply on the new node actually joining `etcd` and reporting healthy before it returns — confirmed live (`dbg`, 2026-10-11): adding a second control-plane node to an existing single-control-plane environment this way took about 40s end to end (VM creation + Talos bootstrap + join), with no manual intervention needed. Verify directly afterward anyway (`kubectl get nodes`, `talosctl etcd members`).
- **Ramp down**: follow [Node replacement](#3-node-replacement) steps 1, 2 and 4 above (drain + graceful `etcd leave` first, then remove the entry and apply) — ramping down is just a replacement with no new node added afterward. Watch for the same stale-`Node`-object gotcha (step 4 there) if `terragrunt apply` complains about cluster health after a successful-looking destroy.

## 5. Moving a node to another Proxmox host

Relocating a node's physical placement (`host_node` in its `terragrunt.hcl` entry) without changing its logical identity otherwise — distinct from [node replacement](#3-node-replacement), which swaps the node itself (new name/IP/VM ID), though the two procedures overlap heavily for a control-plane node.

This is also distinct from changing only a node's **`datastore`** (storage pool) with `host_node` left unchanged: that's an in-place move attempt rather than a destroy/recreate, and hits a different, currently-unresolved limitation — Proxmox refuses to move the EPHEMERAL/attached data-VM disks through the Talos VM, since it isn't their owner. See the module's [storage docs](https://github.com/isejalabs/terraform-proxmox-talos/blob/main/docs/storage.md#changing-the-datastore-of-an-existing-node--ownership-limitation-on-attached-disks) for the error and manual workaround, and [#1615](https://redirect.github.com/isejalabs/homelab/issues/1615) for the homelab context it came up in.

- **Worker node**: change `host_node` in place on the existing entry and `terragrunt apply`. This is a **destroy and recreate** (never a live migration): the Talos VM *and* its data VM, with the Longhorn disk, are created new and empty on the target host. That is no HA concern for the cluster itself, but it **is** for Longhorn: the node loses every replica it held, and its Longhorn disk needs to be re-registered, see [Longhorn disk of a replaced or moved worker](#longhorn-disk-of-a-replaced-or-moved-worker). Move one worker at a time.
- **Control-plane node in a single-control-plane environment**: changing `host_node` in place would mean destroying and recreating the *only* control-plane node directly — a full control-plane outage for the duration, and real quorum risk if anything goes wrong mid-move. The safe path, **confirmed working end to end** (`dbg`, moving its sole control-plane from `pve6` to `pve1`, 2026-10-11):
  1. Add a second, interim control-plane node on the target host (per [Ramp up](#4-ramping-control-planeworker-node-count-up-or-down) above) and confirm it's healthy and in `etcd`.
  2. Gracefully retire the original (per [Node replacement](#3-node-replacement) steps 1, 2 and 4 — drain, `etcd leave`, remove its entry, apply, clean up the stale `Node` object if needed).

  This keeps the environment on 2 control-plane nodes only for the brief overlap window, never on zero, and avoids quorum risk entirely. It does **not** need a temporary second-controlplane-node workaround for etcd bootstrapping reasons — `terraform-proxmox-talos` v6.0+ already supports upgrading/changing a single-control-plane cluster without one (see the module's [Upgrade Methods](https://github.com/isejalabs/terraform-proxmox-talos/blob/main/docs/upgrade%20methods.md#steps-to-upgrade-talos-os) doc) — the interim node here is purely about avoiding a control-plane outage window, not a technical requirement of the tooling.

  **Two real blockers found while verifying this, worth knowing about rather than mistaking for a fundamental limitation**: neither was the control-plane VIP being unreachable, nor skipping the `etcd leave` step (both were suspected going in) —
  - The `bpg/proxmox` Terraform provider needs direct SSH access (not just the Proxmox API) to the *target* Proxmox host for some disk operations when creating the new VM — if the session's `ssh-agent` has no key authorized there, VM creation fails with `unable to authenticate user "root" over SSH`, even though everything else (API calls, Talos bootstrap) would have worked fine.
  - The stale-`Node`-object gotcha from [Node replacement](#3-node-replacement) step 4 applies here identically when retiring the original node.

### Longhorn disk of a replaced or moved worker

Observed 2026-10-11/13 when the `*-work-03` nodes of `dev`, `qa` and `prod` were moved from `pve6` to `pve5`: the data VM's zvols were created new (the Longhorn disk held 0.7 MB to 323 MB afterwards), Longhorn kept its old record of the disk, found a different disk UUID and marked the disk `Ready=False, DiskFilesystemChanged` (`kubectl get nodes.longhorn.io -n longhorn-system -o yaml`, `status.diskStatus`). Nothing recovers by itself: replicas stay at the reduced count (`ROBUSTNESS: degraded`, `numberOfReplicas` 3 for `longhorn-ha` cannot be satisfied with the node out) until the disk is re-registered. Steps, to be done for **each moved worker, one at a time**. The full procedure, including the eviction step before the move, has since been verified exhaustively by moving `rebuild`'s cluster nodes.

**Before the move**

1. All volumes `healthy`: `kubectl get volumes.longhorn.io -n longhorn-system`. Do not start while anything is degraded.
2. Check the free space of the *other* nodes (`status.diskStatus.*.storageAvailable` of `nodes.longhorn.io`) against what the leaving node holds (`scheduledReplica`); the disks are only 20-30 GB. A 3-replica volume (`longhorn-ha`) cannot place its third replica on a 3-worker cluster once one node is out, so it stays degraded for the duration; decide that consciously (these hold the important data, for example `powerdns`).
3. Stop scheduling on the node's disk and ask Longhorn to evict its replicas (Longhorn UI: Node → Edit node and disks, or `spec.disks.<id>.allowScheduling: false` and `evictionRequested: true`), wait until the evictable volumes are `healthy` again and their replicas have left the disk. Volumes with as many replicas as there are workers (for example `powerdns` with 3 on 3 workers) keep their replica on the node: there is nowhere to rebuild it, so it disappears with the move and the volume runs `degraded` until the disk is re-registered. Eviction briefly attaches detached volumes (the `kopiur-cache-*` ones); they detach again afterwards (verified on `rebuild`, 2026-10-13).
   Then drain the node (`kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`).

**After the move** (the new node is `Ready` in Kubernetes)

4. A worker moved in place keeps its Kubernetes `Node` object, so the cordon of the drain survives the move: `kubectl uncordon <node>` (the node shows `Ready,SchedulingDisabled` otherwise). Do this **as soon as the node is `Ready`, while `terragrunt apply` is still waiting**, or before re-running it: the module's `talos_cluster_health` check includes "all k8s nodes to report schedulable" and otherwise fails after 10 minutes with just `cluster health check failed ... context deadline exceeded` (confirmed on `rebuild`, 2026-10-13; `talosctl health --control-plane-nodes <ip> --worker-nodes <ips>` names the failing check).
5. The Longhorn node object still exists with the old disk record. Longhorn refuses to delete a disk that is still schedulable ("Please disable the disk ... and remove all replicas and backing images first"), so disable it first, then remove the entry and add the same path again (no replicas or backing images may be on it; the eviction before the move ensured that, and on a freshly recreated node there are none):
   ```sh
   kubectl -n longhorn-system patch nodes.longhorn.io <node> --type merge \
     -p '{"spec":{"disks":{"<disk-id>":{"allowScheduling":false}}}}'     # e.g. default-disk-082000000000
   kubectl -n longhorn-system patch nodes.longhorn.io <node> --type merge \
     -p '{"spec":{"disks":{"<disk-id>":null}}}'
   until kubectl -n longhorn-system patch nodes.longhorn.io <node> --type merge \
     -p '{"spec":{"disks":{"<disk-id>":{"path":"/var/mnt/longhorn","diskType":"filesystem","allowScheduling":true,"evictionRequested":false}}}}'; do sleep 3; done
   ```
   The last command has to be retried: right after the removal Longhorn's webhook answers `spec and status of disks on node <node> are being syncing and please retry later` (confirmed on `qa`, 2026-10-13), hence the `until ... do sleep` loop.
   (the same can be done in the Longhorn UI). Check that `Ready` and `Schedulable` are `True` for the disk.
6. Longhorn rebuilds the missing replicas onto the new disk. Wait until every volume is `healthy` again (`status.rebuildStatus` of the engine shows the progress) **before moving the next node**.
7. Housekeeping that showed up: a corrupted cache volume of kopiur (`kopiur-cache-<app>`, filesystem errors at mount) keeps its backup pod in `ContainerCreating`; the cache is disposable. Delete the stuck kopiur `Snapshot` (job, pod and the temporary `<app>-<timestamp>-src` volume go with it), the cache PVC, its retained PV and the Longhorn volume; kopiur recreates the cache and runs the next backup.

## Verify the change actually took

- `kubectl get nodes` — the replaced/upgraded node shows `Ready`, running the expected Talos/Kubernetes version (`kubectl get nodes -o wide`).
- `flux get ks -A`/`flux get hr -A` — everything `READY=True`, nothing stuck on the node that changed.
- For a control-plane change: `talosctl --nodes <any-control-plane-ip> etcd members` shows exactly the expected member set, no stale entries left behind.
- For a node replacement that carried Longhorn replicas: `kubectl get volumes.longhorn.io -n longhorn-system` shows `ROBUSTNESS: Healthy` again, not just that the new node is `Ready`.
