---
status: current
---

# Node lifecycle: Talos/Kubernetes upgrades and node replacement

**On this page:** [Upgrade Talos](#1-talos-os-upgrade) · [Staging a multi-step upgrade on one branch](#staging-a-multi-step-upgrade-on-one-branch) · [Upgrade Kubernetes](#2-kubernetes-version-upgrade) · [Replace a node](#3-node-replacement) · [Scale node count](#4-ramping-control-plane-worker-node-count-up-or-down) · [Move a node to another Proxmox host](#5-moving-a-node-to-another-proxmox-host) · [Verify](#verify-the-change-actually-took)

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

   **This step is not optional — confirmed via real data corruption, not just a theoretical gap.** Observed 2026-10-14 during the `v1.13.11` Talos OS rollout: a node carrying `unifi/mongodb` was upgraded without draining first. The VM's hard `stop_on_destroy` killed `mongod` mid-write; it came back with `"Detected unclean shutdown - Lock file is not empty"`, then a real WiredTiger I/O error (`"Structure needs cleaning"`) and a fatal assertion — the database itself was corrupted, not just briefly unavailable. Longhorn's own volume health reported `robustness: healthy` throughout (it auto-salvaged/remounted fine); the corruption was one layer up, at the application/filesystem level, where Longhorn's health check doesn't look. Recovery needed a full restore from the app's latest kopiur backup (`just backup::kopiur::restore <app> -e <env> -n <namespace>` — see [`kopiur-backup-restore.md`](kopiur-backup-restore.md)). Skipping drain "to save time" risks exactly this for any single-replica stateful workload.

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

### Staging a multi-step upgrade on one branch

Following the step-by-step above literally (control planes first, one node at a time, finalize last) for an environment with several nodes means several sequential `terragrunt apply`s before the environment reaches its new steady state. The repo's own convention — [apply only from `main`](../AGENTS.md) — would otherwise mean one PR+merge per node (plus one more for the prep/finalize steps): for `prod`'s 3 control planes + 3 workers, that's 8 separate PRs for what is conceptually one change (moving the environment from version A to version B). Worse, several of those PRs end up reformatting lines the step didn't conceptually touch at all — `tofu fmt`/`terragrunt hcl format` realigns every `=` in a block whenever any key in it changes length (e.g. temporarily unsetting `cluster.talos_machine_config_version`, or temporarily moving the leader-election patch to a per-node `talos_config_patches` entry so each control plane can switch independently — see the module's [Interaction with `talos_machine_config_version`](https://github.com/isejalabs/terraform-proxmox-talos/blob/main/docs/upgrade-methods.md#interaction-with-talos_machine_config_version) doc for why multi-control-plane environments need that), so the PR history fills with wide-looking diffs that are mostly whitespace.

This is sanctioned as the one standing exception to [AGENTS.md's apply-from-`main` rule](../AGENTS.md): capture the whole upgrade on a single dedicated branch, applying each step directly from that branch, and squash-merge into `main` only once the rollout is fully done. **This is a process rule, not an agent-specific one — a human operator doing this upgrade by hand follows the identical steps**, which is why it lives here (the shared runbook) rather than only in `AGENTS.md`.

1. Branch off current `main`: `git checkout -b chore/<env>-talos-<version>-upgrade`.
2. **Prep commit**: bump `image.update_version` to the target version; if `cluster.talos_machine_config_version` is pinned, unset it for the duration (see the module doc linked above for why); if the environment has more than one control plane and a config patch that has a version-specific variant, move it from the global `talos_config_patches` to each control plane's own per-node `talos_config_patches` entry (still pointing at the pre-upgrade variant — a pure refactor at this point, verify the plan shows no resource changes). Push, open the PR now (so CI validates every commit you push from here on), but don't merge yet.
3. **One commit per node**, control planes first: set that node's `update = true` (and, for a control plane, switch its own `talos_config_patches` entry to the version-specific variant). Push, then `terragrunt apply` **directly from this branch** — the exception in question. Verify the plan is scoped to just that node (and the shared-host image artifact, see the module's `proxmox_download_file` lifecycle note) before applying, and verify cluster/pod health before the next commit. Don't skip ahead even though it's tempting since nothing is merged yet — the whole point is that each step is still independently verified, just not independently merged.
4. **Finalize commit**: converge `image.version` to match `image.update_version`, clear every node's `update` flag, re-pin `cluster.talos_machine_config_version` to the new version if you unset it in step 2, and consolidate any per-node patch back to a single global `talos_config_patches` entry now that every node agrees on the variant. Rebase the branch onto `main` first if anything else landed there while the rollout was in progress (a Renovate PR touching the same file is the likely case), and re-check the plan's scope after rebasing rather than assuming it's still fine. Apply from the branch and confirm the plan converges to a no-op (or only the usual Flux-vs-Terraform namespace drift).
5. Squash-merge the branch into `main`. Since squashing erases the per-node commits from `main`'s history, write the PR description as the step-by-step record instead (which node, in what order, any incident hit along the way) — that's the only place this detail survives once merged.

**Scope of the exception**: this covers exactly this procedure — a staged, node-by-node Talos OS or Kubernetes version rollout. It is not a general license to apply other kinds of changes to `prod`/`qa` from a branch; every other change still goes through the normal PR-before-apply flow. Keep the branch open only for the duration of the rollout itself — don't let it linger once the environment has converged.

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

This is also distinct from changing only a node's **`datastore`** (storage pool) with `host_node` left unchanged: a plain flip is an in-place move attempt that fails for the data-VM disks, see [Changing the datastore of a node](#changing-the-datastore-of-a-node) for what to do instead ([#1615](https://redirect.github.com/isejalabs/homelab/issues/1615) has the homelab context).

- **Worker node**: change `host_node` in place on the existing entry and `terragrunt apply`. This is a **destroy and recreate** (never a live migration): the Talos VM *and* its data VM, with the Longhorn disk, are created new and empty on the target host. That is no HA concern for the cluster itself, but it **is** for Longhorn: the node loses every replica it held, and its Longhorn disk needs to be re-registered, see [Longhorn disk of a replaced or moved worker](#longhorn-disk-of-a-replaced-or-moved-worker). Move one worker at a time.
- **Control-plane node in a single-control-plane environment**: changing `host_node` in place would mean destroying and recreating the *only* control-plane node directly — a full control-plane outage for the duration, and real quorum risk if anything goes wrong mid-move. The safe path, **confirmed working end to end** (`dbg`, moving its sole control-plane from `pve6` to `pve1`, 2026-10-11):
  1. Add a second, interim control-plane node on the target host (per [Ramp up](#4-ramping-control-planeworker-node-count-up-or-down) above) and confirm it's healthy and in `etcd`.
  2. Gracefully retire the original (per [Node replacement](#3-node-replacement) steps 1, 2 and 4 — drain, `etcd leave`, remove its entry, apply, clean up the stale `Node` object if needed).

  This keeps the environment on 2 control-plane nodes only for the brief overlap window, never on zero, and avoids quorum risk entirely. It does **not** need a temporary second-controlplane-node workaround for etcd bootstrapping reasons — `terraform-proxmox-talos` v6.0+ already supports upgrading/changing a single-control-plane cluster without one (see the module's [Upgrade Methods](https://github.com/isejalabs/terraform-proxmox-talos/blob/main/docs/upgrade%20methods.md#steps-to-upgrade-talos-os) doc) — the interim node here is purely about avoiding a control-plane outage window, not a technical requirement of the tooling.

  **Two real blockers found while verifying this, worth knowing about rather than mistaking for a fundamental limitation**: neither was the control-plane VIP being unreachable, nor skipping the `etcd leave` step (both were suspected going in) —
  - The `bpg/proxmox` Terraform provider needs direct SSH access (not just the Proxmox API) to the *target* Proxmox host for some disk operations when creating the new VM — if the session's `ssh-agent` has no key authorized there, VM creation fails with `unable to authenticate user "root" over SSH`, even though everything else (API calls, Talos bootstrap) would have worked fine.
  - The stale-`Node`-object gotcha from [Node replacement](#3-node-replacement) step 4 applies here identically when retiring the original node.

  **Verified again on `rebuild` and `dev`** (2026-10-13), each time with an interim `ctrl-02` on `pve4` (the standard location of any `-02` node), then the original `ctrl-03` moved to `pve6` (the interim node is retired the same way; `dev` additionally got the etcd disk on another datastore this way, see [Changing the datastore of a node](#changing-the-datastore-of-a-node)):
  - The stale-`Node` gotcha is not optional: the apply that removes the retired node **always fails** the first time with `cluster health check failed`. Delete the `Node` (`kubectl delete node <name>`) and run `terragrunt plan` / `apply` again, it then converges.
  - `talosctl etcd members` before `etcd leave` and after: the retiring node must be the only entry that disappears. Run `etcd leave` on the node that leaves.
  - Re-adding a node with the *same* name, IP and VM ID after retiring it works: the destroy removes the data VM as well, so there is no leftover disk (checked on `dev`: nothing remains on the old storage).
  - Adding a control-plane node makes Talos re-apply the machine config on the workers; the CRI restarts there and Longhorn volumes on a worker can flap `attached`/`unknown` for about 5 minutes (`rebuild`, 2026-10-13). Wait until all attached volumes are `healthy` before the next step.
  - **Changing the storage (`datastore`) of an existing node**: not in place, see [Changing the datastore of a node](#changing-the-datastore-of-a-node).

### Changing the datastore of a node

The storage a node's disks live on is set per node by `datastore` (workers: `local.datastore`, control planes: `local.ctrl_datastore`, both defaulting to `local-enc` from `terragrunt/_envcommon/vehagn-k8s.hcl`). The block size of a zvol is fixed at creation, so a different block size means a different storage. The 4K storage `local-zfs-4k` was tried for etcd and is not used any more: the A/B test in [#1615](https://redirect.github.com/isejalabs/homelab/issues/1615) measured about 11 to 12% *more* physical write amplification than with 16K, so control planes go back to the default (`local-enc`, 16K) with this procedure.

**Do not just change `datastore` on an existing node and apply.** That is planned as an in-place update. Proxmox moves the disks the Talos VM owns (OS disk, cloud-init), but refuses the EPHEMERAL/attached disks of the data VM (`Cannot move ... it is not owned by this VM!`, [isejalabs/terraform-proxmox-talos#258](https://redirect.github.com/isejalabs/terraform-proxmox-talos/pull/258), reproduced in both directions on `dbg-work-03`) and leaves a half-moved node behind. Always replace the node's disks instead; both paths below create fresh disks on the new storage and are verified.

- **Control-plane node: through an interim control-plane node** (verified on `dev`, `local-enc` to `local-zfs-4k`, 2026-10-13/14, no etcd downtime; the other direction works the same, the original node also moved from `pve5` to `pve6` on the way). Same procedure as the [control-plane move](#5-moving-a-node-to-another-proxmox-host) above, with the new storage in the entries:
  1. Add the interim node (for example `ctrl-02` on `pve4`) with `datastore = local.ctrl_datastore` set to the **new** storage. Keep the `datastore` of the original node **unchanged** while doing this, otherwise the same plan tries to move its disks and fails. Apply, check `kubectl get nodes` and `talosctl etcd members` show both.
  2. Drain the original node, `talosctl etcd leave` on it, remove or comment out its entry, apply. The first apply fails the health check because of the stale `Node` (see [Node replacement](#3-node-replacement) step 4): `kubectl delete node <name>`, run `terragrunt plan`/`apply` again.
  3. Add the original node again (same name, IP and VM ID are fine, the destroy removed its data VM) with the new storage, apply, wait for it to join `etcd`.
  4. Retire the interim node the same way as in step 2.
- **Worker node: replace both VMs** (verified on `dbg-work-03`, `local-zfs-4k` to `local-enc`, 2026-10-14). Set the new `datastore` in the entry, then plan and apply with the Talos VM and the data VM named for replacement:
  ```sh
  terragrunt plan -out=tfplan \
    -replace='module.talos.proxmox_virtual_environment_vm.this["<node-fqdn>"]' \
    -replace='module.talos.proxmox_virtual_environment_vm.data_vm["<node-fqdn>"]'
  terragrunt apply tfplan
  ```
  Check in the plan that only that node's VM, data VM and machine configuration are replaced. The node comes back **empty** (the Longhorn disk included), so treat it like a [moved worker](#longhorn-disk-of-a-replaced-or-moved-worker): evict and drain before (drain's cordon survives, `kubectl uncordon` afterwards), re-register the Longhorn disk after, one worker at a time. A cluster without Longhorn data (for example `dbg`) needs none of that.
- **If the data must survive in place** (no replacement possible): the manual, out-of-band `qm set` repoint documented in the module's [storage docs](https://github.com/isejalabs/terraform-proxmox-talos/blob/main/docs/storage.md#changing-the-datastore-of-an-existing-node--ownership-limitation-on-attached-disks). Not used so far; Terraform state and Proxmox must agree afterwards, so check with a plan.

**Check afterwards:** `pvesm list <storage>` on the Proxmox host shows the node's volumes (OS disk, cloud-init, the data VM's disk `<vmid>0`) on the new storage and nothing is left on the old one; for a block size change `zfs get volblocksize <pool>/<volume>` shows the expected value; `terragrunt plan` shows no infrastructure changes (only the usual in-place namespace updates).

#### If the datastore was flipped in Terraform anyway

A plain `datastore` flip fails at the data VM's disks (see above) and leaves a half-moved node. Observed on `rebuild-ctrl-03` (2026-10-15, `local-zfs-4k` back to `local-enc`), VM `7008173`, data VM `70081730`, both stopped:

- Talos VM: `ide2` (cloud-init) on `local-enc`, `scsi0` (OS disk) and `scsi1` (data disk) still on `local-zfs-4k`.
- Data VM: `scsi0` on `local-enc` (moved copy, created at the move), while the Talos VM's `scsi1` still points to the `local-zfs-4k` copy, which the node actually ran with. `pvesm list` shows `vm-70081730-disk-0` on both storages.
- `terragrunt plan` wants to move the OS disk (`local-zfs-4k` to `local-enc`) and start the VM.

The generic guideline, with the choice between keeping the copy on the new datastore (variant A) or the live copy (variant B), is in the module doc [Recovering a node with a flipped datastore](https://github.com/isejalabs/terraform-proxmox-talos/blob/main/docs/storage.md#recovering-a-node-with-a-flipped-datastore) (to be merged with [isejalabs/terraform-proxmox-talos#278](https://redirect.github.com/isejalabs/terraform-proxmox-talos/pull/278)). Which copy: the moved copy on `local-enc` was made at 15:41 while the node was still running, the node was shut down gracefully about 50 seconds later, so the copy lags by that last minute. `rebuild` has a single control plane, so variant B (keep the live copy) is the safe choice here. The commands with the real values, run on `pve6`:

```sh
qm config 7008173 > /root/qm-7008173.before; qm config 70081730 > /root/qm-70081730.before
# 1. drop the lagging copy on local-enc
qm set 70081730 --delete scsi0
qm unlink 70081730 --idlist unused0 --force 1
# 2. attach the live copy (local-zfs-4k) to the data VM
qm set 70081730 --scsi0 'local-zfs-4k:vm-70081730-disk-0,aio=io_uring,backup=1,cache=writethrough,discard=on,iothread=1,replicate=1,size=6G,ssd=1'
# 3. move it through its owner, source stays as unused0
qm disk move 70081730 scsi0 local-enc
# 4. point the Talos VM at the moved volume
qm set 7008173 --scsi1 'local-enc:vm-70081730-disk-0,aio=io_uring,backup=1,cache=writethrough,discard=on,iothread=1,replicate=1,size=6G,ssd=1'
```

Then `terragrunt apply` for `rebuild` (it moves the OS disk, which the Talos VM owns, and starts the VM; run `kubectl uncordon` if the node was drained), wait for `Ready`, check `pvesm list local-enc` / `local-zfs-4k` and a clean `terragrunt plan`, and only then free the old copy: `qm unlink 70081730 --idlist unused0 --force 1`.

**Verified 2026-10-17 on `pve6`:** At the start of verification, the repair commands 1–4 and the `rebuild` apply were already reflected in the live configs, so they were not replayed: VM 7008173 was running with its OS disk and data disk on `local-enc`; data VM 70081730 was stopped with `scsi0` on `local-enc` and the former `local-zfs-4k` disk as `unused0`. All four Kubernetes nodes reported `Ready`. The targeted `terragrunt plan -target='module.talos'` reported no changes; a full plan in this fresh checkout is blocked by the intentionally absent, gitignored sealed-secrets certificate/key pair (see [`terragrunt/README.md`](../terragrunt/README.md), which documents targeted planning for this case). After those checks, `qm unlink 70081730 --idlist unused0 --force 1` removed the old copy: `pvesm list` now shows `vm-70081730-disk-0` only on `local-enc`, no entry on `local-zfs-4k`, and all four Kubernetes nodes remained `Ready`.

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
