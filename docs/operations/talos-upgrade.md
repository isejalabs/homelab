---
status: current
---

# Runbook: Talos OS upgrade

**On this page:** [Scope](#scope) · [1. Compatibility check](#1-compatibility-check) · [2. Plan the rollout](#2-plan-the-rollout) · [3. Upgrade one environment](#3-upgrade-one-environment) · [4. Verify](#4-verify) · [5. Roll on and close out](#5-roll-on-and-close-out) · [Known issues](#known-issues)

How to move the fleet to another Talos version: what to check first, in which order Talos and Kubernetes have to move, how the version pins and the Renovate pull requests fit in, in which order to roll environments, and what to verify afterwards. The mechanics of upgrading one cluster (the per-node `update` flag, drain, the staged upgrade branch) are in [`node-lifecycle.md`](node-lifecycle.md#1-talos-os-upgrade) and are not repeated here. This runbook is the companion of [`k8s-minor-upgrade.md`](k8s-minor-upgrade.md) and has the same shape.

## At a glance

| | |
| --- | --- |
| When to use | Moving the fleet to another Talos version, patch or minor. For the steps on one cluster alone use [`node-lifecycle.md`](node-lifecycle.md#1-talos-os-upgrade); for a Kubernetes minor use [`k8s-minor-upgrade.md`](k8s-minor-upgrade.md) |
| Prerequisites | A [compatibility check](#1-compatibility-check) with every row satisfied (for a patch: the release notes read), the environment's Kubernetes minor inside the window of the target Talos, a healthy cluster with every Longhorn volume `Healthy`, a fresh restore point, Terragrunt access and `talosctl` contexts for the environment |
| Steps | [Plan the rollout](#2-plan-the-rollout), [upgrade one environment](#3-upgrade-one-environment) node by node on one upgrade branch, then [roll on](#5-roll-on-and-close-out). Expected output is recorded in [`node-lifecycle.md`](node-lifecycle.md#staging-a-multi-step-upgrade-on-one-branch): each plan is limited to one node, and the plan after the finalize commit is a no-op |
| Verify | [Verify](#4-verify) |
| Rollback | None documented as a procedure. A node that fails on the new version can be recreated on the old one by reverting its commit on the upgrade branch and applying again (not exercised). Stop the rollout and fix the cause instead of rolling on |
| Last exercised | The rollout mechanics: `v1.13.11` in `dev` and `prod` ([#1643](https://github.com/isejalabs/homelab/issues/1643), 2026-10-14) and `v1.14.2` in `qa` ([PR #1655](https://github.com/isejalabs/homelab/pull/1655), 2026-10-14) and the other non-prod environments ([PR #1679](https://github.com/isejalabs/homelab/pull/1679), 2026-10-15). This runbook as a whole, with its compatibility check and rollout order, has not been followed end to end yet |

## Scope

Talos is pinned per environment in `terragrunt/<tier>/eu-central-1/<env>/vehagn-k8s/terragrunt.hcl` with three values: `image.version` (what a node runs), `image.update_version` (what a node with `update = true` is moved to) and `cluster.talos_machine_config_version` (the format of the generated machine config). In the steady state all three are equal.

Rules that apply throughout:

- **Talos and Kubernetes are upgraded separately, and the order is planned.** A Talos upgrade does not change the Kubernetes version. Each Talos minor supports only a window of Kubernetes minors, so one of the two can block the other (see [Kubernetes window](#kubernetes-window-which-one-moves-first)).
- **One Talos minor at a time.** Move to the latest patch of the current minor first, then to the next minor (the [upstream upgrade notes](https://docs.siderolabs.com/talos/v1.14/configure-your-talos-cluster/lifecycle-management/upgrading-talos) describe the supported path; switch to the target minor in the URL).
- **Order: non-prod first, `qa` immediately before `prod`.** Rolling out `prod` without a clean `qa` is not an option.
- **Node by node, control planes first, drained first.** The module replaces the node's VM, which is a hard stop for everything on it ([`node-lifecycle.md`](node-lifecycle.md#1-talos-os-upgrade), step 2).
- Do not start a Talos upgrade in the middle of a Kubernetes upgrade, or the other way round.

## 1. Compatibility check

Decide the target version, then confirm **every** row below. Read the installed versions from the repo, not from memory. Record the result in the tracking issue. For a patch within the same Talos minor, the release notes of the patches in between and the first two rows are enough.

| Component | Where pinned | Check | Notes |
| --- | --- | --- | --- |
| **Kubernetes** | `cluster.kubernetes_version` in each environment's `vehagn-k8s/terragrunt.hcl` | [Talos support matrix](https://docs.siderolabs.com/talos/v1.14/getting-started/support-matrix), row `Kubernetes` (switch to the target Talos minor in the URL) | The hard limit, see [Kubernetes window](#kubernetes-window-which-one-moves-first). Environments differ in their Kubernetes version, so check each one |
| **`terraform-proxmox-talos` module** | `source = "...terraform-proxmox-talos.git?ref=vX.Y.Z"` in each environment | The module's [Talos compatibility](https://github.com/isejalabs/terraform-proxmox-talos/blob/main/docs/talos-compatibility.md) matrix and its per-version caveats, and the [release notes](https://github.com/isejalabs/terraform-proxmox-talos/releases) | The module generates the whole machine config from the Talos version on every apply, so a new Talos minor can need a new module version first. Bump the module as its own change ([Terraform Module Version Upgrade](https://github.com/isejalabs/terraform-proxmox-talos/blob/main/docs/upgrade-methods.md#terraform-module-version-upgrade)) and test module source changes in `src` |
| **Machine config patches** | `talos_config_patches` in each environment, files under [`terragrunt/_envcommon/vehagn-k8s/talos-patches/`](../../terragrunt/_envcommon/vehagn-k8s/talos-patches) | *What's new* and the configuration reference of the target minor | A field that moves or disappears needs a variant of the patch for the new version, added before the rollout (example: `leader-election-1.14.yaml` for Talos 1.14) |
| **Schematic and system extensions** | `image.schematic_path`, `assets/talos/schematic.yaml` in each environment (`qemu-guest-agent`, `iscsi-tools`, `util-linux-tools`) | The [Image Factory](https://factory.talos.dev/) offers each extension for the target version; *What's new* for renamed or removed extensions | Longhorn needs `iscsi-tools` and `util-linux-tools` on every node. A schematic change is its own procedure ([Talos Schematic Upgrade](https://github.com/isejalabs/terraform-proxmox-talos/blob/main/docs/upgrade-methods.md#talos-schematic-upgrade)); do not combine it with the version bump |
| **Cilium** | `k8s/infra/kube-system/cilium/base/ocirepository.yaml` | [Cilium system requirements](https://docs.cilium.io/en/stable/operations/system_requirements/) against the kernel of the target Talos (*What's new* names it) | Cilium depends on the kernel, not on Talos itself. The `hostDNS` setting in `cluster.machine_features` exists because of a Cilium issue; check that it still applies |
| **Longhorn** | `k8s/infra/longhorn-system/longhorn-core/base/helmrelease.yaml` | [Longhorn on Talos](https://longhorn.io/docs/latest/advanced-resources/os-distro-specific/talos-linux-support/) for the deployed Longhorn version | Depends on the extensions above, kernel modules and the kubelet mounts the module configures. All volumes `Healthy` before and after |
| **Proxmox CSI plugin** | `k8s/infra/csi-proxmox/proxmox-csi/base/ocirepository.yaml` | [proxmox-csi-plugin](https://github.com/sergelogvinov/proxmox-csi-plugin) releases | Talks to the Proxmox API and attaches disks to the VM; affected by the VM being recreated rather than by the Talos version. Check that volumes attach again after a worker was replaced |
| **Security defaults of the new minor** | generated by the module from the Talos version | *What's new* of the target minor and the module's per-version caveats | A new minor can switch a default on for an existing cluster, because the config is regenerated (example: `workloadIsolation` with Talos 1.14). Check `hostPath` workloads such as the Checkmk node collector afterwards |
| **Proxmox side** | Proxmox VE version of the hosts, VM settings in the module | The module's release notes; the image datastore has room for the new image | The new image is downloaded to the Proxmox hosts as part of the first apply (`proxmox_download_file`), so every host that carries a node of the environment has to be up and have room for it |

### Kubernetes window: which one moves first

Each Talos minor supports about five Kubernetes minors, and the window moves up by one with every Talos minor. From the support matrix (read on 2026-11-17): Talos 1.13 supports Kubernetes 1.31 to 1.36, Talos 1.14 supports 1.33 to 1.37. Two cases follow:

- **The environment's Kubernetes minor is below the window of the target Talos:** Kubernetes has to move first ([`k8s-minor-upgrade.md`](k8s-minor-upgrade.md)), one minor at a time, until it is inside the window. Only then start the Talos upgrade. An environment left on an old Kubernetes minor is what blocks the *next* Talos minor, so look one Talos minor ahead when planning and raise the lagging environments in time.
- **The wanted Kubernetes minor is above the window of the current Talos:** Talos has to move first, then Kubernetes.

Check the window for every environment in the rollout, not only for `prod`: the Kubernetes versions differ between environments, and the ones outside the regular maintenance track are usually the oldest. Compare each environment's `cluster.kubernetes_version` with the lower end of the target window.

## 2. Plan the rollout

1. **Open an umbrella issue** (`chore(talos): roll out Talos <version> to all environments`) with the compatibility table from step 1 filled in, and one sub-issue per environment linked as real GitHub sub-issues. Branch and PR names follow [`AGENTS.md`](../../AGENTS.md).
2. **Renovate proposes, a person upgrades.** `siderolabs/talos` is never auto-merged ([`update-handling.md`](update-handling.md#non-standard-update-strategies)). Renovate raises one PR per environment with the label `updateStrategy:manual`, and it changes only the lines that carry a `# renovate:` comment: `image.update_version` and `cluster.talos_machine_config_version`, not `image.version` and no node's `update` flag.

   > [!WARNING]
   > **Do not merge and apply such a Renovate PR as it is.** A pinned `talos_machine_config_version` applies to every node at once, whatever its `update` flag says ([module doc](https://github.com/isejalabs/terraform-proxmox-talos/blob/main/docs/upgrade-methods.md#interaction-with-talos_machine_config_version)), so the staging would be lost for the config format. Treat the PR as the notice that a version exists, make the change on the upgrade branch as described in [step 3](#3-upgrade-one-environment), and close the Renovate PR once the environment's own PR is merged (Renovate closes it by itself when the versions match).

3. **Roll out in this order**, one environment at a time, finishing the verify step before the next:

   | Order | Environment | Why |
   | --- | --- | --- |
   | 1 | `dev` | cheap to break; shows config, extension and CNI problems first |
   | 2 | `qa` | closest to `prod`, `main`-only apply; a clean `qa` is the gate for `prod` |
   | 3 | `prod` | last, after a soak of `qa`, with a fresh kopiur backup |

   `dbg` is left out of the rollout (it is for ad-hoc debugging); it, `rebuild`, `src` and `poc` follow whenever convenient, and for an environment that is shut down or destroyed the rules in [`k8s-minor-upgrade.md`](k8s-minor-upgrade.md#environments-that-may-not-be-running-on-demand) apply. `head` tracks the newest Talos by itself and is the early warning, not the proof.

## 3. Upgrade one environment

The procedure is [`node-lifecycle.md` §1](node-lifecycle.md#1-talos-os-upgrade), run as [one staged upgrade branch](node-lifecycle.md#staging-a-multi-step-upgrade-on-one-branch): a prep commit, one commit and one apply per node, a finalize commit, then a squash-merge. For `prod` and `qa` this is the one sanctioned exception to applying from `main`. What that section does not spell out per version value:

| Commit | `image.version` | `image.update_version` | `cluster.talos_machine_config_version` | node `update` |
| --- | --- | --- | --- | --- |
| Before | old | old | old | unset |
| Prep | old | **new** | **unset**, so that each node's config format follows its own `update` flag ([module doc](https://github.com/isejalabs/terraform-proxmox-talos/blob/main/docs/upgrade-methods.md#interaction-with-talos_machine_config_version)) | unset |
| Per node | old | new | unset | `true` on this node and on the ones already done |
| Finalize | **new** | new | **new** | unset on all nodes |

Before the first node:

- **Pre-flight**: nodes `Ready`, `talosctl health`, etcd members complete, Flux `Ready`, no failing pods, every Longhorn volume `Healthy`. The triage of an environment that is not clean is the same as for Kubernetes: [Pre-flight triage](k8s-minor-upgrade.md#pre-flight-triage-do-not-start-on-an-unexplained-not-clean-cluster).
- **Fresh restore point**: Longhorn snapshots and a kopiur backup of each stateful app, as in [`k8s-minor-upgrade.md`](k8s-minor-upgrade.md#3-upgrade-one-environment).
- **Read every plan.** It must be limited to the one node (plus the image download per Proxmox host). For unrelated drift use `-exclude` as described under [Plan before apply](k8s-minor-upgrade.md#3-upgrade-one-environment).

> [!CAUTION]
> **Drain each node before its apply**, and have a control plane leave etcd first. The apply stops the VM hard; an undrained node with a single-replica database on it has already cost a restore from backup ([`node-lifecycle.md`](node-lifecycle.md#1-talos-os-upgrade), step 2).

An environment with a single control plane (`dev`, `qa`) has no API server while that node is replaced. That is expected; wait for it to come back before judging anything else.

## 4. Verify

After each node, before the next one:

```sh
kubectl get nodes -o wide                       # the node is Ready and shows the new OS image
talosctl --context <env>-homelab -n <node-ip> version
talosctl --context <env>-homelab -n <ctrl-ip> etcd members    # after a control plane
kubectl get volumes.longhorn.io -n longhorn-system            # multi-replica volumes Healthy again
```

After the finalize commit, on the whole environment:

| Area | Check | Where to look |
| --- | --- | --- |
| Nodes | all `Ready`, all on the new Talos version, Kubernetes version unchanged | [`node-lifecycle.md`](node-lifecycle.md#verify-the-change-actually-took) |
| Terraform | `terragrunt plan` is a no-op apart from known drift | [`node-lifecycle.md`](node-lifecycle.md#staging-a-multi-step-upgrade-on-one-branch), step 4 |
| Extensions | `talosctl get extensions` lists the three extensions of the schematic on every node | [compatibility check](#1-compatibility-check) |
| Cilium / networking | `cilium status`; an existing `HTTPRoute` answers; DNS resolves from a pod | [`architecture/network.md`](../architecture/network.md) |
| Flux | `flux get ks -A` and `flux get hr -A` all `Ready` | [`troubleshooting-flux.md`](../troubleshooting/troubleshooting-flux.md) |
| Storage | Longhorn volumes `Healthy`; a Proxmox CSI volume is attached and mounted on a replaced worker | [`troubleshooting-storage.md`](../troubleshooting/troubleshooting-storage.md) |
| Stateful apps | no restart loops, no unclean-shutdown messages in the database logs | [`architecture/workloads.md`](../architecture/workloads.md) |
| Backups | the first scheduled kopiur backup after the upgrade succeeded for every stateful app | [`kopiur-backup-restore.md`](../backup/kopiur-backup-restore.md) |
| Monitoring | Checkmk services of the cluster and its nodes are back to their state from before; node collectors (`hostPath`) report | [`k8s-minor-upgrade.md`](k8s-minor-upgrade.md#checkmk-what-supported-means-and-how-to-test-it) |

## 5. Roll on and close out

- Repeat steps 3 and 4 for the next environment. Between `qa` and `prod` the soak rule of [`k8s-minor-upgrade.md`](k8s-minor-upgrade.md#5-roll-on-to-the-next-environment) applies: at least one night, at most about three days.
- Squash-merge each environment's upgrade branch as soon as that environment has converged, and write the per-node record into the PR description.
- Kubernetes can follow once Talos is done everywhere ([`node-lifecycle.md`](node-lifecycle.md#2-kubernetes-version-upgrade) recommends keeping the two aligned), as its own rollout.
- Update the docs that state the Talos version ([`reference/environments.md`](../reference/environments.md) and what `git grep` finds for the old version), the matrix URL in this runbook when the Talos minor changed, and note the final versions in the umbrella issue.
- If you hit something not covered here, add it to this runbook in the same PR.

## Known issues

- **A node upgraded without draining corrupted a database** (`v1.13.11` rollout, 2026-10-14). Longhorn reported the volume healthy throughout; the damage was in the application's files. Details and recovery: [`node-lifecycle.md`](node-lifecycle.md#1-talos-os-upgrade), step 2.
- **The data VM is not touched by the upgrade**, only the Talos VM is recreated, so `EPHEMERAL` and the Longhorn disk survive. A plan that wants to change or destroy a data VM or a volume is not an upgrade plan: stop and find out why before applying.
- **A Longhorn disk can need re-registration on a replaced worker**: [Longhorn disk of a replaced or moved worker](node-lifecycle.md#longhorn-disk-of-a-replaced-or-moved-worker).
- **Version-specific machine config changes** are collected per Talos minor in the module's [Talos compatibility](https://github.com/isejalabs/terraform-proxmox-talos/blob/main/docs/talos-compatibility.md) doc (Talos 1.14: multi-document config, `workloadIsolation`). Read the section of every minor the upgrade crosses.
- **Fresh worktree**: the plan fails on the missing sealed-secrets certificate files; see the last entry under [Known issues](k8s-minor-upgrade.md#known-issues) of the Kubernetes runbook.
