---
status: current
---

# Node lifecycle: Talos/Kubernetes upgrades and node replacement

How to move one environment from one pinned Talos/Kubernetes version to another, and how to replace a single node, in an otherwise-healthy cluster. Not a full cluster rebuild — see [`disaster-recovery.md`](disaster-recovery.md) for that, and [`architecture/environments.md`](architecture/environments.md) for what each environment is and why `prod` gets stricter rules (`main`-checkout-only applies, no `track-branch` override) than the others.

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
4. **Clean up Longhorn's record of the departed node**, if it ran any Longhorn replicas — Longhorn doesn't always remove its own `nodes.longhorn.io` object just because the underlying Kubernetes `Node` is gone. See [`troubleshooting-storage.md`](troubleshooting-storage.md#2-a-longhorn-volume-degraded-or-faulted) for checking replica health; Longhorn rebuilds any replica that was on the departed node onto a healthy one automatically, but give it time to do so and confirm `ROBUSTNESS: Healthy` before considering the replacement fully done.

## Verify the change actually took

- `kubectl get nodes` — the replaced/upgraded node shows `Ready`, running the expected Talos/Kubernetes version (`kubectl get nodes -o wide`).
- `flux get ks -A`/`flux get hr -A` — everything `READY=True`, nothing stuck on the node that changed.
- For a control-plane change: `talosctl --nodes <any-control-plane-ip> etcd members` shows exactly the expected member set, no stale entries left behind.
- For a node replacement that carried Longhorn replicas: `kubectl get volumes.longhorn.io -n longhorn-system` shows `ROBUSTNESS: Healthy` again, not just that the new node is `Ready`.
