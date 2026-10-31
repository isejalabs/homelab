---
status: current
---

# Runbook: Kubernetes minor version upgrade

**On this page:** [Scope](#scope) · [Which method per environment](#which-method-per-environment) · [1. Compatibility check](#1-compatibility-check) · [2. Plan the pin and the rollout](#2-plan-the-pin-and-the-rollout) · [3. Upgrade one environment](#3-upgrade-one-environment) · [4. Verify](#4-verify) · [5. Roll on to the next environment](#5-roll-on-to-the-next-environment) · [6. Close out](#6-close-out) · [Working with an agent](#working-with-an-agent) · [Known issues](#known-issues)

How to move the fleet from one Kubernetes **minor** (e.g. `1.34` → `1.35`) — the part around the actual upgrade command: what to check first, how to change the Renovate pin, in which order to roll environments, and what to verify afterwards. The mechanics of upgrading one cluster (`talosctl upgrade-k8s`, then `terragrunt apply`) are in [`node-lifecycle.md`](node-lifecycle.md#2-kubernetes-version-upgrade) and are not repeated here. A *patch* bump (`1.34.6` → `1.34.11`) needs only that section, not this runbook.

## Scope

Kubernetes is pinned per environment in `cluster.kubernetes_version` of `terragrunt/<tier>/eu-central-1/<env>/vehagn-k8s/terragrunt.hcl`, and is deliberately never auto-updated (see [`update-handling.md`](update-handling.md#non-standard-update-strategies)). Two things hold it at a minor: the `kubernetes/kubernetes` pin in [`.github/renovate/pin-versions.json5`](../../.github/renovate/pin-versions.json5), and the compatibility of the components below. `head` and `poc` are exempt from the pin and run ahead of everything else, so they are the early warning, not the proof (see [`environments.md`](../reference/environments.md)).

Rules that apply throughout:

- **One minor at a time.** Never skip a minor (`1.34` → `1.36`); kubelet may lag the API server by the [version skew policy](https://kubernetes.io/releases/version-skew-policy/) but the upgrade path is still minor by minor.
- **Order: non-prod first, `qa` immediately before `prod`.** Rolling out `prod` without a clean `qa` is not an option.
- **Apply from `main`, and merge close to the upgrade.** A Kubernetes minor is one imperative `talosctl upgrade-k8s` followed by one declarative reconcile, so the staged-upgrade exception in [`AGENTS.md`](../../AGENTS.md) (it exists to avoid one PR per node in a node-by-node Talos rollout) is not needed. Merge the PR right after a clean dry run, run `upgrade-k8s`, then `terragrunt apply` **from `main`** (a reconcile that only records what `upgrade-k8s` already did). In the 2-step method never apply before `upgrade-k8s` has finished, because the machine-config change would update all nodes at once, which the imperative rolling upgrade exists to avoid. Order: dry run clean, merge, `upgrade-k8s`, apply from `main`, verify. Which environments use which method: [next section](#which-method-per-environment).
- Do not start a Kubernetes minor upgrade in the middle of a Talos upgrade (the two are decoupled on purpose, see [`node-lifecycle.md`](node-lifecycle.md#1-talos-os-upgrade)).

## Which method per environment

Two methods exist. **2-step**: `talosctl upgrade-k8s` (rolling, one node at a time), then `terragrunt apply` from `main` to record it. **1-step**: merge the PR, then `terragrunt apply` from `main` only; Talos updates the nodes from the new machine config, with no separate rolling step.

| Environment | Method | Why |
| --- | --- | --- |
| `prod` | 2-step | HA (3 control planes). The rolling step is what keeps the API available; applying alone could restart all three API servers at about the same time (not verified, and not something to test on `prod`) |
| `qa` | 2-step | The rehearsal for `prod`: if it uses another procedure, a clean `qa` says little about `prod`. Its topology (1 control plane + 3 workers) is the same as `dev`'s, so the reason is purpose, not danger |
| `dev`, `rebuild`, `src`, `dbg` (and `poc`, `head`) | 1-step | One control plane, so the API server restarts either way, and the cost of breaking it is a rebuild |

Evidence for the 1-step method so far: one run, `dev` on 2026-10-21 ([isejalabs/homelab#1812](https://github.com/isejalabs/homelab/pull/1812)). All 4 nodes were on v1.35.9 within about 3 minutes, one worker lagged by about a minute, and the plan afterwards was clean. That is one clean run, not proof; API availability during the apply was not measured. Revisit this table if a 1-step run ever goes wrong.

How to choose when an environment is not listed: **Is it HA? Is it a rehearsal for `prod`? What does a rebuild cost?** If in doubt, or if the environment holds data you cannot recreate, use 2-step.

The 1-step method still needs: a health check before (nodes Ready, Flux, no failing pods), `terragrunt plan` from `main` limited to the machine-config updates, and afterwards nodes on the new version, a clean second plan, Flux Ready and no new failing pods. A restore point and the Checkmk before/after comparison are for environments with data or monitoring you care about.

### Environments that may not be running (on-demand)

After merging a version bump, check read-only whether the cluster is running, then:

- **Running:** apply from `main` (1-step) so the live cluster does not drift from git.
- **Not running (shut down):** never start it on your own. Ask the owner, with these options: start it and apply; leave it (git is already correct, so the next start applies from `main`; only a cluster that is not running differs); delete it as housekeeping; skip.
- **Does not exist (destroyed):** nothing to do, a bump in git is enough because the next create uses the new version.
- **`rebuild`:** always ask, because a rebuild may be in progress and cannot be told from outside.

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

1. **Open an umbrella issue** (`chore(k8s): roll out Kubernetes <minor> to all environments`) with the compatibility table from step 1 filled in, and one **sub-issue per environment** linked as real GitHub sub-issues (example: [isejalabs/homelab#1798](https://github.com/isejalabs/homelab/issues/1798)). The umbrella is the memory of which environments are still open; Renovate PRs are not a substitute, because they carry neither the procedure nor the order. Branch and PR names follow [`AGENTS.md`](../../AGENTS.md) (`issue/<n>_<slug>`, `Closes #<n>`).
2. **Raise the Renovate pin** in [`pin-versions.json5`](../../.github/renovate/pin-versions.json5), in its own PR. **When:** after the compatibility check, including Checkmk, has been verified on the first non-prod environment, and at the latest before `prod` starts; the pin exists because of Checkmk, so that verification is its expiry condition. Raise it by one minor (never remove it): that bounds any mishap (a broken merge setup) to a version already verified, and nothing is applied automatically anyway:
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

The 2-step upgrade itself is [`node-lifecycle.md` §2](node-lifecycle.md#2-kubernetes-version-upgrade): `talosctl upgrade-k8s`, then reconcile `cluster.kubernetes_version` with `terragrunt apply` (for the 1-step environments see [Which method per environment](#which-method-per-environment)). The notes below are what that section does not cover, taken from the `prod` `1.34.6` → `1.34.11` rollout (see [#1747](https://github.com/isejalabs/homelab/issues/1747)).

- **One PR per environment** (`issue/<n>_<slug>`, `Closes #<n>`), merged and applied from `main` as described under [Scope](#scope). The PR only records the target version and what was verified; do not gate its merge on post-upgrade results (backups, Checkmk), those gate the *next* environment.
- **No wrapper script.** `scripts/upgrade-k8s.sh` was removed ([#1806](https://github.com/isejalabs/homelab/pull/1806)): run `talosctl upgrade-k8s` per environment with an explicit `--context`. The Kubernetes version CI validates manifests against is `K8S_VERSION` in `scripts/kustomize-build-all.sh`; bump it when the fleet moves to the new minor.
- **Talos access**: use the named contexts in `~/.talos/config` (`prod-homelab`, `qa-homelab`, ...) with an explicit `--context`, rather than changing the current context. Check `talosctl config contexts` first; if the environment is missing, merge its talosconfig as described in [`terragrunt/README.md`](../../terragrunt/README.md#talosconfig).
- **Fresh restore point before the first node**: `just backup::longhorn-snapshot::create --all -A -e <env>` (manual snapshot of every Longhorn volume; delete them after the soak, see [`longhorn-snapshots.md`](../backup/longhorn-snapshots.md)) and `just backup::kopiur::create <app> -e <env> -n <ns>` for each stateful app, waiting for `Succeeded`. A kopiur snapshot can hang in `Running` when its mover pod lands on another node than the strict-local staged volume ([isejalabs/homelab#1797](https://github.com/isejalabs/homelab/issues/1797)): delete that `Snapshot` and trigger a new one. If `unifi-mongodb` fails with `PermissionDenied`, see [isejalabs/homelab#1794](https://github.com/isejalabs/homelab/pull/1794) (`mongosh` must not run as root).
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
  - If it shows unrelated drift, do **not** apply that: use `-exclude=module.<name>` for the unrelated module and note the drift in the PR. The usual case in every `vehagn-k8s` environment is the bootstrap modules stripping the Flux labels/annotations (`kustomize.toolkit.fluxcd.io/*`) from the `csi-proxmox` and `sealed-secrets` namespaces, so plan and apply with both excluded:
    ```sh
    terragrunt plan -exclude=module.proxmox_csi_plugin -exclude=module.sealed_secrets -out=<scratch>/plan.tfplan
    terragrunt apply <scratch>/plan.tfplan
    ```
    This also makes the gitignored sealed-secrets cert/key unnecessary in a fresh `main` checkout (see [Known issues](#known-issues)). Do not copy them in or generate a new keypair just for this, a different keypair than the live one breaks every `SealedSecret`.
  - A saved plan (`-out=...`) applied afterwards guarantees what you reviewed is what runs.
- **After the apply, `terragrunt plan` must come back clean** (apart from any excluded drift). A non-empty plan means the cluster and state disagree.

### Pre-flight triage: do not start on an unexplained "not clean" cluster

"No *new* issues after the upgrade" is not enough of a bar: an issue that exists before the upgrade can hide the effect of the upgrade, or be made worse by it. Before the first command, list **every** non-OK item and give it a tier. Put the table in the tracking issue; the sign-off on that table is the explicit "yes, proceed despite these" for the environment.

Where to collect the items:
- the environment's Checkmk site (`prod_k8s` etc.): all services with state above OK, also the stale-looking hosts;
- `kubectl get nodes`, `kubectl get pods -A --field-selector='status.phase!=Running,status.phase!=Succeeded'`, `kubectl get ks,hr -A` (anything not `True`);
- Longhorn volumes (`robustness` other than `healthy` on attached ones) and the kopiur snapshots (`kubectl get snapshots.kopiur.home-operations.com -A`, look at the newest per app);
- the disk fill of the control-plane nodes (see below).

| Tier | Meaning | Examples | Rule |
| --- | --- | --- | --- |
| **Blocker** | Would be a risk or hide a risk of the upgrade | not Ready node or missing etcd member; Flux/Longhorn degraded; stateful app without a successful backup in the last day; removed API still in use; a control-plane disk that cannot hold the new images | Fix it first, do not proceed |
| **Understand first** | Touches storage, backups, control plane, networking or the monitoring of the cluster itself | a failed kopiur snapshot; a Checkmk service on a Kubernetes component; a WARN on a control-plane filesystem | Find the cause, write it down; proceed only with a stated reason |
| **Ignore** | Cosmetic or unrelated to the cluster | a stale Checkmk host for a removed DaemonSet; a threshold WARN far from critical on a non-critical disk | Note it in the table, no further action |

Two things learned from the first runs that belong in this triage:
- **A failed snapshot can be a harmless file permission problem, but you must know that.** On `prod` a daily `unifi-mongodb` snapshot failed with `PermissionDenied` on five `.mongodb/mongosh/*_log` files inside the data volume (left behind by someone running `mongosh` in the pod); the previous days and a manual backup afterwards succeeded. Read `status.failure` of the snapshot (`kubectl get snapshots.kopiur.home-operations.com <name> -n <ns> -o jsonpath='{.status.failure}'`), and take a fresh successful backup right before the upgrade regardless.
- **Control-plane disks are small (about 6 GiB) and old and new images coexist after an upgrade.** `talosctl image list --namespace cri` on a control plane shows both the old and the new `kube-apiserver`, `kube-controller-manager` and `kube-scheduler`; the old ones are only removed by kubelet image garbage collection (it starts at 85% disk usage). A control plane already at about 80% (the Checkmk default warn) will probably cross that line during the upgrade; that is survivable but should be a conscious decision, not a surprise CRIT.

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
| Cilium / networking | `cilium status`; an existing `HTTPRoute` answers; DNS resolves from a pod | [`architecture/network.md`](../architecture/network.md) |
| Flux | `flux get ks -A` and `flux get hr -A` all `Ready`; nothing stuck `Reconciling` | [`troubleshooting-flux.md`](../troubleshooting/troubleshooting-flux.md) |
| Storage | all Longhorn volumes `Healthy`; a PVC binds and mounts; a snapshot works | [`troubleshooting-storage.md`](../troubleshooting/troubleshooting-storage.md), [`longhorn-snapshots.md`](../backup/longhorn-snapshots.md) |
| Secrets & certs | `ExternalSecret`s `SecretSynced`; `Certificate`s `Ready` | — |
| Backups | the first scheduled kopiur backup after the upgrade succeeded for every stateful app, plus a restore dry-run for one app. A failure is a gate for the next environment, not for merging this PR | [`kopiur-backup-restore.md`](../backup/kopiur-backup-restore.md) |
| Monitoring | before/after comparison of services and agent sections ([see below](#checkmk-what-supported-means-and-how-to-test-it)); `checkmk-agent` pods Ready | Checkmk UI |
| Apps | each user-facing app responds; stateful apps (databases) have no restart loops | [`architecture/workloads.md`](../architecture/workloads.md) |

### Checkmk: what "supported" means and how to test it

Checkmk states support per minor (it supports four Kubernetes minors at a time) and announces a new Kubernetes minor in a Werk, some time after its release. "Supported" therefore means "covered by Checkmk's own tests and fixes", not "will work in our setup", and a patch-level fix that enables a new minor can land in a specific site patch: take the newest patch of the site's minor (no need to hunt for the exact one) and read the Werks since your current patch for Kubernetes entries. Because a quiet failure mode is likely (a section that stops being parsed disappears rather than turning CRIT), a service that stays OK is not enough evidence. Compare *before* and *after* instead, on the environment's Kubernetes host in the site:

1. **Before** the upgrade, record the baseline (query the services; `cmk -d <host>` on a Kubernetes cluster host can take minutes, so do not rely on it for the baseline and run it in the background if you want the section list): the service list with states and the agent sections. For example on the site (replace the host name):
   ```sh
   printf 'GET services\nFilter: host_name = <k8s-host>\nColumns: description state has_been_checked\n' | lq | sort > before-services.txt
   cmk -d <k8s-host> | grep '^<<<' | sort | uniq -c > before-sections.txt
   ```
2. **After**, repeat into `after-*.txt` and `diff` them. Expect no services gone, none `PENDING`/stale, no new `UNKNOWN`, and no section missing; new services are fine.
3. Spot-check content, not just state: the cluster shows the new Kubernetes version, the node count is right, a known workload shows its pod count, and node metrics (CPU/memory via the node collector) have fresh data points.
4. Check the special agent's own output: `cmk -vv --debug -d <k8s-host>` shows API errors or parse failures that never reach a service.

Do this in the earlier environments first. Each environment has its own Checkmk site (`dev_k8s` and `qa_k8s` on `monitoring1`, `prod_k8s` on `monitoring2`; see the [observability audit](../audits/2026-09-observability-phase0-checkmk-proxmox-claude.md)), so a `qa` run only predicts `prod` if `qa_k8s` runs the same Checkmk minor/patch as `prod_k8s`. Upgrade the earlier sites first. The hosts to compare are each environment's cluster host plus the hosts piggybacked from it (nodes, deployments, namespaces, daemonsets); names are listed in [`reference/environments.md`](../reference/environments.md#checkmk-monitoring-of-the-clusters).

**Baseline the `prod` site as well, not only the `*_k8s` site.** The `prod` site queries the same clusters with its own Kubernetes special agent (see [`reference/environments.md`](../reference/environments.md#the-prod-site-also-queries-the-clusters)), so the cluster host and its piggybacked hosts exist twice and can differ. Run the before/after steps above on both sites. Two things are expected there and are not upgrade findings:

- A short `CRIT` on the cluster host (`Failed to establish a connection at URL https://<env>-homelab-k8s-api...`) while the API server restarts during the node upgrades. It must be back to `Success` once the upgrade finished; a state that stays CRIT or UNKNOWN afterwards is a finding.
- `Missing data` on hosts for namespaces, deployments or PVCs that no longer exist. The hosts in `prod` are added by hand and are not removed when the workload goes away, so list them in the baseline (tier *Ignore*) and clean them up separately.

If something fails: stop, do **not** roll on, and roll forward by fixing the cause. Kubernetes minor downgrades are not supported; the realistic fallbacks are fixing the failing component or rebuilding the environment from state ([`disaster-recovery.md`](../backup/disaster-recovery.md)).

## 5. Roll on to the next environment

Repeat steps 3 and 4 for the next row of the table in [step 2](#2-plan-the-pin-and-the-rollout). Between `qa` and `prod`:

- **Soak `qa` for a bounded time, not an open-ended one.** Minimum about 22 hours and **at least one night in between**, so the nightly cron jobs and the kopiur backup runs have run on the new version; maximum about 3 days, so the environments do not drift apart and the upgrade keeps its momentum (prod once sat on an old patch version for a long time because the next step was left waiting). The time is only a floor for the *events* you need to observe; what counts is the quality of the checks: the [Verify](#4-verify) list passed, the Checkmk before/after comparison is clean, and the first scheduled backups after the upgrade succeeded. If those are done after one night, there is no reason to wait longer.
- Confirm a recent successful kopiur backup for every stateful app in `prod`, and that Longhorn volumes are `Healthy`.
- Do the `prod` upgrade in a quiet window, control planes first, as the upgrade command does by itself.

## 6. Close out

- Make sure the PR of each environment was squash-merged (right after its dry run, before the upgrade), and that the Renovate PRs for those environments are closed or superseded.
- Update docs that state the Kubernetes version or pin: [`update-handling.md`](update-handling.md#non-standard-update-strategies), [`reference/environments.md`](../reference/environments.md), and anything else that `git grep` finds for the old minor.
- Note in the tracking issue the final versions per environment and any component you had to upgrade first.
- If you hit something not covered here, add it to this runbook in the same PR.

## Working with an agent

For an agent-driven rollout (for example with Claude Code):

- **The state lives in the umbrella and sub-issues, not in the chat.** The agent reads them and the live cluster and re-verifies; it does not trust a brief or a remembered number.
- **One fresh session per environment**, briefed with the umbrella, the environment's sub-issue and this runbook. Every turn re-processes the whole conversation, so a long session gets expensive: with about 500k tokens of context, a small dev bump of roughly 20 tool calls used about 4 points of the 5-hour limit. Keep one session only for tightly coupled steps of a single environment.
- **Pick the follow-up method by need:** a fork for a noisy side investigation (it inherits the history, so it costs as much per turn as the parent); a handover document (issue or PR) for multi-day or multi-environment work; compact only after exact values (IDs, snapshot names, Checkmk baselines) are saved in an issue or file.
- **Persist baselines and decisions outside the chat**: the Checkmk before-snapshot, the restore point names and the pre-flight triage belong in the sub-issue or PR.
- **The agent never starts a shut-down cluster, and asks about `rebuild`** (see above).

## Known issues

- **`cilium-install` Job: `field is immutable`.** At the end of `talosctl upgrade-k8s` (and in `--dry-run`), the manifest sync fails to re-apply the inline Cilium install Job because its `spec.template` is immutable. The node upgrades have already happened by then; check the kubelet versions as shown in [step 3](#3-upgrade-one-environment) rather than relying on the exit code. Tracked in [isejalabs/terraform-proxmox-talos#204](https://github.com/isejalabs/terraform-proxmox-talos/issues/204).
- **Flux Kustomization stuck on "Reconciliation in progress" after the control plane restarted.** On a single-control-plane environment (`qa`, `dev`, ...) the kube-apiserver is briefly gone during the upgrade. A Kustomization that was mid-reconcile can fail with `failed to update status: timed out waiting for the condition` and then sit in `Reconciling`/`Unknown` with its next retry an hour away, and its dependants stay `dependency not ready`. Nothing is wrong with the cluster: request a normal reconcile (`kubectl annotate ks <name> -n flux-system reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite`) and re-check `kubectl get ks,hr -A`.
- **`zsh` does not word-split `$VAR`**, so `T="--context x -n y"; talosctl $T ...` fails with a usage error; spell the flags out when scripting from zsh.
- **`talosctl health` reports "unexpected nodes"** when only `--control-plane-nodes` is passed and the cluster has workers. Pass `--worker-nodes` too.
- **Terragrunt plan fails on missing `sealed-secrets.cert`/`.key`** in a fresh worktree: those gitignored files live only in the main checkout (`.../vehagn-k8s/assets/sealed-secrets/certificate/`). Exclude `module.sealed_secrets` (and `module.proxmox_csi_plugin`, for the same namespace drift) as described under [Plan before apply](#3-upgrade-one-environment), or scope the command with `-target=module.talos`; both were verified to plan without the files. Do not generate a new keypair.
