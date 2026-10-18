---
status: current
---

# Runbook: Kubernetes minor version upgrade

**On this page:** [Scope](#scope) · [1. Compatibility check](#1-compatibility-check) · [2. Plan the pin and the rollout](#2-plan-the-pin-and-the-rollout) · [3. Upgrade one environment](#3-upgrade-one-environment) · [4. Verify](#4-verify) · [5. Roll on to the next environment](#5-roll-on-to-the-next-environment) · [6. Close out](#6-close-out) · [Known issues](#known-issues)

How to move the fleet from one Kubernetes **minor** (e.g. `1.34` → `1.35`) — the part around the actual upgrade command: what to check first, how to change the Renovate pin, in which order to roll environments, and what to verify afterwards. The mechanics of upgrading one cluster (`talosctl upgrade-k8s`, then `terragrunt apply`) are in [`node-lifecycle.md`](node-lifecycle.md#2-kubernetes-version-upgrade) and are not repeated here. A *patch* bump (`1.34.6` → `1.34.11`) needs only that section, not this runbook.

## Scope

Kubernetes is pinned per environment in `cluster.kubernetes_version` of `terragrunt/<tier>/eu-central-1/<env>/vehagn-k8s/terragrunt.hcl`, and is deliberately never auto-updated (see [`update-handling.md`](update-handling.md#non-standard-update-strategies)). Two things hold it at a minor: the `kubernetes/kubernetes` pin in [`.github/renovate/pin-versions.json5`](../.github/renovate/pin-versions.json5), and the compatibility of the components below. `head` and `poc` are exempt from the pin and run ahead of everything else, so they are the early warning, not the proof (see [`environments.md`](reference/environments.md)).

Rules that apply throughout:

- **One minor at a time.** Never skip a minor (`1.34` → `1.36`); kubelet may lag the API server by the [version skew policy](https://kubernetes.io/releases/version-skew-policy/) but the upgrade path is still minor by minor.
- **Order: non-prod first, `qa` immediately before `prod`.** Rolling out `prod` without a clean `qa` is not an option.
- **`prod` and `qa` apply from `main`** — except the staged-upgrade exception in [`AGENTS.md`](../AGENTS.md), which this procedure uses (see [step 3](#3-upgrade-one-environment)).
- Do not start a Kubernetes minor upgrade in the middle of a Talos upgrade (the two are decoupled on purpose, see [`node-lifecycle.md`](node-lifecycle.md#1-talos-os-upgrade)).

## 1. Compatibility check

Decide the target minor, then confirm **every** row below supports it. A row is satisfied only when its upstream document names the target minor as supported for the version *currently deployed* — otherwise the component must be upgraded first (as its own change, in its own PR), or the minor upgrade waits. Record the result in the tracking issue.

Read the installed version from the repo, not from memory — the versions drift. The "Where pinned" column says where.

| Component | Where pinned | Check compatibility | Notes |
| --- | --- | --- | --- |
| **Talos Linux** | `image.version` / `update_version` / `talos_machine_config_version` in each env's `vehagn-k8s/terragrunt.hcl` | [Talos support matrix](https://docs.siderolabs.com/talos/v1.14/getting-started/support-matrix) (switch to the deployed Talos minor in the URL) | The hard limit. If the target minor is not listed for the deployed Talos, upgrade Talos first ([`node-lifecycle.md`](node-lifecycle.md#1-talos-os-upgrade)). |
| **`terraform-proxmox-talos` module** | `source = "...terraform-proxmox-talos.git?ref=vX.Y.Z"` in each env | The module's [Talos compatibility matrix](https://github.com/isejalabs/terraform-proxmox-talos/blob/main/docs/talos-compatibility.md) and [release notes](https://github.com/isejalabs/terraform-proxmox-talos/releases) | It templates the machine config and bootstraps the inline Cilium; check it knows the target minor. Module bumps are manual. |
| **Cilium** | `k8s/infra/kube-system/cilium/base/ocirepository.yaml` (tag), plus the Renovate pin `quay.io/cilium/charts/cilium` | [Cilium Kubernetes compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/) | Replaces kube-proxy and carries all traffic; a bad pairing breaks the whole cluster. If a Cilium upgrade is needed, do it first, in `qa`, on its own. |
| **Gateway API CRDs** | `gateway_api_version` in `terragrunt/_envcommon/vehagn-k8s.hcl`, plus the Renovate pin `kubernetes-sigs/gateway-api` | [Gateway API releases](https://github.com/kubernetes-sigs/gateway-api/releases) and Cilium's supported Gateway API version | The CRD version must be one Cilium supports, independent of the Kubernetes minor, but check the CRDs still install on the new API server. |
| **Longhorn** | `k8s/infra/longhorn-system/longhorn-core/base/helmrelease.yaml` (chart version) | [Longhorn installation requirements](https://longhorn.io/docs/latest/deploy/install/#installation-requirements) for the deployed version | Stateful workloads sit on it; upgrading Longhorn mid-Kubernetes-upgrade is how data gets hurt. Confirm all volumes `Healthy` before and after. |
| **Checkmk** (the `checkmk-agent` Kubernetes collector, and the Checkmk site) | `k8s/apps/monitoring/checkmk-agent/base/helmrelease.yaml` (chart version); site version on `monitoring2` | [Checkmk Kubernetes monitoring](https://docs.checkmk.com/latest/en/monitoring_kubernetes.html) and the [`checkmk_kube_agent` repo](https://github.com/checkmk/checkmk_kube_agent) | **This is why the Renovate pin exists** (see [`update-handling.md`](update-handling.md)). Two pieces matter: the in-cluster collectors (`checkmk-agent` chart, Python-based) and the special agent that ships with the Checkmk *site* (every site that monitors a cluster: both `prod` and `prod_k8s`). Upgrade both sites to the newest patch of the same minor *before* the Kubernetes upgrade, and see [Checkmk: what "supported" means](#checkmk-what-supported-means-and-how-to-test-it). |
| **Flux** (operator + instance) | `k8s/infra/flux-system/flux-operator` and `.../flux-instance` (`ocirepository.yaml` tag) | [Flux releases](https://fluxcd.io/flux/releases/) and the [flux-operator releases](https://github.com/controlplaneio-fluxcd/flux-operator/releases) | Flux supports all upstream-supported Kubernetes minors; an old Flux can fall out of that window once a minor goes end-of-life. |
| **cert-manager** | `k8s/infra/cert-manager/cert-manager/base/ocirepository.yaml` | [cert-manager supported releases](https://cert-manager.io/docs/releases/) | |
| **External Secrets Operator** | `k8s/infra/external-secrets/external-secrets/base/ocirepository.yaml` | [ESO stability and support](https://external-secrets.io/latest/introduction/stability-support/) | Secrets for nearly every app flow through it. |
| **Sealed Secrets** | `k8s/infra/sealed-secrets/sealed-secrets/base/ocirepository.yaml` | [Sealed Secrets releases](https://github.com/bitnami-labs/sealed-secrets/releases) | |
| **Proxmox CSI plugin** | `k8s/infra/csi-proxmox/proxmox-csi/base/ocirepository.yaml` | [proxmox-csi-plugin](https://github.com/sergelogvinov/proxmox-csi-plugin) README / releases | |
| **Snapshot controller** | `k8s/infra/kube-system/snapshot-controller/base/ocirepository.yaml` | the chart's and [external-snapshotter](https://github.com/kubernetes-csi/external-snapshotter) release notes | Needed for Longhorn/Proxmox volume snapshots (kopiur backups). |
| **kopiur** | `k8s/infra/kopiur-system/kopiur/base/ocirepository.yaml` | [kopiur releases](https://github.com/home-operations/kopiur/releases) | Backups; confirm a fresh backup exists before touching prod. |

Then check what the new version removes or changes — this is independent of the table above:

- Read the target minor's changelog sections *Urgent Upgrade Notes*, *Deprecation* and *API Change*, for example [CHANGELOG-1.35](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.35.md) (replace the minor).
- Check the [deprecated API migration guide](https://kubernetes.io/docs/reference/using-api/deprecation-guide/) for APIs removed in the target minor, then look for them in use on the *current* cluster:
  ```sh
  kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis
  ```
  A non-empty result names an API still being called; find the caller (usually an operator or chart that needs its own upgrade) before proceeding.
- Run `kustomize build` on the app overlays (CI's `kustomize-build` does this) — it will not catch removed *cluster* APIs, which is why the metric above matters.
- Look at Helm charts and CRDs that pin a Kubernetes minimum: `kubeVersion` in the chart, or `kubectl api-resources` differences between a current and a freshly upgraded `qa`.

## 2. Plan the pin and the rollout

1. **Open a tracking issue** (`chore: upgrade Kubernetes to <minor>`) with the compatibility table from step 1 filled in. Branch and PR names follow [`AGENTS.md`](../AGENTS.md) (`issue/<n>_<slug>`, `Closes #<n>`).
2. **Lift the Renovate pin** in [`pin-versions.json5`](../.github/renovate/pin-versions.json5), in its own PR, once the compatibility check is clean:
   - `keep kubernetes at an older version due to checkmk` — raise `allowedVersions` (`<=1.34` → `<=1.35`).
   - `allow latest versions of kubernetes for HEAD and PoC` — raise the floor to match (`>=1.34` → `>=1.35`).
   - Update the matching row in [`update-handling.md`](update-handling.md#non-standard-update-strategies) and, if the pin reason changed (e.g. Checkmk now supports it), the rule `description`.
   - Pin the other packages the check found you must hold back (Cilium, Gateway API) in the same PR if they are not already held.
3. **Let Renovate raise per-environment PRs.** `kubernetes/kubernetes` PRs carry `updateStrategy:manual` and are never auto-merged; there is one per environment's `terragrunt.hcl`. Use them as the starting point for each environment's change rather than hand-editing, and close the ones you are not acting on yet.
4. **Roll out in this order**, one environment at a time, finishing the verify step before the next:

   | Order | Environment | Why |
   | --- | --- | --- |
   | 1 | `dev` | the usual maintenance track starts here; cheap to break, surfaces API and chart problems |
   | 2 | `qa` | closest to `prod`: more apps, same backup schedules, `main`-only apply. A clean `qa` is the gate for `prod` |
   | 3 | `prod` | last; soak `qa` for a few days first, and have a fresh kopiur backup |

   `dbg` is left out of the rollout (it is for ad-hoc debugging), and `rebuild` follows whenever convenient. When `dev` is busy with parallel feature work, the first run may swap the first two rows (`qa` first), accepting that `qa` is then the first environment to see problems; say so in the tracking issue.

   `head` and `poc` are already ahead of the pin and are not part of the rollout.

## 3. Upgrade one environment

The upgrade itself is [`node-lifecycle.md` §2](node-lifecycle.md#2-kubernetes-version-upgrade): `talosctl upgrade-k8s`, then reconcile `cluster.kubernetes_version` with `terragrunt apply`. The notes below are what that section does not cover, taken from the `prod` `1.34.6` → `1.34.11` rollout (see [#1747](https://github.com/isejalabs/homelab/issues/1747)).

- **Use one upgrade branch per environment for `qa` and `prod`**, applied from the branch and squash-merged into `main` once converged, exactly as in [`node-lifecycle.md`](node-lifecycle.md#staging-a-multi-step-upgrade-on-one-branch). Everything else follows [`AGENTS.md`](../AGENTS.md).
- **Talos access**: use the named contexts in `~/.talos/config` (`prod-homelab`, `qa-homelab`, ...) with an explicit `--context`, rather than changing the current context. Check `talosctl config contexts` first; if the environment is missing, merge its talosconfig as described in [`terragrunt/README.md`](../terragrunt/README.md#talosconfig).
- **Pre-flight, every environment**:
  ```sh
  talosctl --context <env>-homelab -n <ctrl-ip> health \
    --control-plane-nodes <ctrl-ips> --worker-nodes <worker-ips>
  talosctl --context <env>-homelab -n <ctrl-ip> etcd members
  ```
  Stop on any unhealthy node, missing etcd member, or Longhorn volume that is not `Healthy`.
- **Dry-run first**: `talosctl ... upgrade-k8s --to <version> --dry-run`. It prints the per-node plan (`kubelet: <old> -> <new>`). It takes a few minutes and prints nothing until the end when piped; run it in the background. It is expected to end with the `cilium-install` error described under [Known issues](#known-issues), not to be treated as a failed pre-flight.
- **Run the upgrade**, then confirm every node reports the new kubelet before applying Terraform:
  ```sh
  talosctl --context <env>-homelab -n <all-node-ips> get kubeletspec -o yaml | grep -E '^node:|image:'
  ```
- **Plan before apply, and read it.** In a fresh checkout the plan also shows `local_file` outputs as new (the local cache is empty) — that is noise. What must appear is one in-place `talos_machine_configuration_apply` per node and nothing else you did not expect.
  - If it shows unrelated drift (for example Flux labels/annotations being stripped from a namespace by the bootstrap module), do **not** apply that: use `-exclude=module.<name>` for the unrelated module and note the drift in the PR.
  - A saved plan (`-out=...`) applied afterwards guarantees what you reviewed is what runs.
- **After the apply, `terragrunt plan` must come back clean** (apart from any excluded drift). A non-empty plan means the cluster and state disagree.

## 4. Verify

Everything below must pass on an environment before moving on. Cluster-level:

```sh
kubectl get nodes -o wide                       # all Ready, all on the new version
talosctl --context <env>-homelab -n <ctrl-ip> health --control-plane-nodes ... --worker-nodes ...
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
cilium status                                    # or: kubectl -n kube-system get ds cilium
kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis
```

Then per area, in this order (platform first, apps last):

| Area | Check | Where to look |
| --- | --- | --- |
| API server / etcd | `kubectl get --raw='/readyz?verbose'`; etcd members all present | — |
| Cilium / networking | `cilium status`; an existing `HTTPRoute` answers; DNS resolves from a pod | [`architecture/network.md`](architecture/network.md) |
| Flux | `flux get ks -A` and `flux get hr -A` all `Ready`; nothing stuck `Reconciling` | [`troubleshooting-flux.md`](troubleshooting-flux.md) |
| Storage | all Longhorn volumes `Healthy`; a PVC binds and mounts; a snapshot works | [`troubleshooting-storage.md`](troubleshooting-storage.md), [`longhorn-snapshots.md`](longhorn-snapshots.md) |
| Secrets & certs | `ExternalSecret`s `SecretSynced`; `Certificate`s `Ready` | — |
| Backups | a kopiur `SnapshotSchedule` ran after the upgrade; a restore dry-run for one app | [`kopiur-backup-restore.md`](kopiur-backup-restore.md) |
| Monitoring | before/after comparison of services and agent sections ([see below](#checkmk-what-supported-means-and-how-to-test-it)); `checkmk-agent` pods Ready | Checkmk UI |
| Apps | each user-facing app responds; stateful apps (databases) have no restart loops | [`architecture/workloads.md`](architecture/workloads.md) |

### Checkmk: what "supported" means and how to test it

Checkmk states support per minor (it supports four Kubernetes minors at a time) and announces a new Kubernetes minor in a Werk, some time after its release. "Supported" therefore means "covered by Checkmk's own tests and fixes", not "will work in our setup", and a patch-level fix that enables a new minor can land in a specific site patch: take the newest patch of the site's minor (no need to hunt for the exact one) and read the Werks since your current patch for Kubernetes entries. Because a quiet failure mode is likely (a section that stops being parsed disappears rather than turning CRIT), a service that stays OK is not enough evidence. Compare *before* and *after* instead, on the environment's Kubernetes host in the site:

1. **Before** the upgrade, record the baseline: the service list with states and the agent sections. For example on the site (replace the host name):
   ```sh
   echo 'GET services\nFilter: host_name = <k8s-host>\nColumns: description state has_been_checked' | lq | sort > before-services.txt
   cmk -d <k8s-host> | grep '^<<<' | sort | uniq -c > before-sections.txt
   ```
2. **After**, repeat into `after-*.txt` and `diff` them. Expect no services gone, none `PENDING`/stale, no new `UNKNOWN`, and no section missing; new services are fine.
3. Spot-check content, not just state: the cluster shows the new Kubernetes version, the node count is right, a known workload shows its pod count, and node metrics (CPU/memory via the node collector) have fresh data points.
4. Check the special agent's own output: `cmk -vv --debug -d <k8s-host>` shows API errors or parse failures that never reach a service.

Do this in the earlier environments first (their Kubernetes hosts are monitored by the same site, so they are the canary for `prod`).

If something fails: stop, do **not** roll on, and roll forward by fixing the cause. Kubernetes minor downgrades are not supported; the realistic fallbacks are fixing the failing component or rebuilding the environment from state ([`disaster-recovery.md`](disaster-recovery.md)).

## 5. Roll on to the next environment

Repeat steps 3 and 4 for the next row of the table in [step 2](#2-plan-the-pin-and-the-rollout). Between `qa` and `prod`:

- Let `qa` run for several days across at least one kopiur backup cycle, and read the Checkmk view for it.
- Confirm a recent successful kopiur backup for every stateful app in `prod`, and that Longhorn volumes are `Healthy`.
- Do the `prod` upgrade in a quiet window, control planes first, as the upgrade command does by itself.

## 6. Close out

- Merge each environment's upgrade branch (squash) and make sure the Renovate PRs for those environments are closed or superseded.
- Update docs that state the Kubernetes version or pin: [`update-handling.md`](update-handling.md#non-standard-update-strategies), [`reference/environments.md`](reference/environments.md), and anything else that `git grep` finds for the old minor.
- Note in the tracking issue the final versions per environment and any component you had to upgrade first.
- If you hit something not covered here, add it to this runbook in the same PR.

## Known issues

- **`cilium-install` Job: `field is immutable`.** At the end of `talosctl upgrade-k8s` (and in `--dry-run`), the manifest sync fails to re-apply the inline Cilium install Job because its `spec.template` is immutable. The node upgrades have already happened by then; check the kubelet versions as shown in [step 3](#3-upgrade-one-environment) rather than relying on the exit code. Tracked in [isejalabs/terraform-proxmox-talos#204](https://github.com/isejalabs/terraform-proxmox-talos/issues/204).
- **`talosctl health` reports "unexpected nodes"** when only `--control-plane-nodes` is passed and the cluster has workers. Pass `--worker-nodes` too.
- **Terragrunt plan fails on missing `sealed-secrets.cert`/`.key`** in a fresh worktree: those gitignored files live only in the main checkout (`.../vehagn-k8s/assets/sealed-secrets/certificate/`). Plan from a checkout that has them, or exclude the sealed-secrets module for the plan.
