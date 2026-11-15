---
status: current
---

# From zero to a running cluster

The shortest ordered path from nothing to a running, Flux-reconciled cluster, with the result to expect after each step. It only points at the docs that own each step and never repeats their commands, so follow the linked section for the how. Unfamiliar word? See the [glossary](glossary.md).

This is the same sequence as the [full cluster rebuild](backup/disaster-recovery.md#full-cluster-rebuild) in the disaster-recovery guide, minus the recovery-specific steps. If you are recovering a cluster that existed before, use that guide instead.

## 0. Before you start

### Tools

Tool versions are pinned, never repeated in the docs: the root [`.mise.toml`](../.mise.toml), [`terragrunt/.mise.toml`](../terragrunt/.mise.toml) and [`k8s/.mise.toml`](../k8s/.mise.toml) are the source, and `mise install` in the repo root and in those two folders installs them.

| Tool | What it is for | Pinned in |
| --- | --- | --- |
| `opentofu`, `terragrunt` | Provision Proxmox VMs and the Talos install ([`terragrunt/README.md`](../terragrunt/README.md)) | [`terragrunt/.mise.toml`](../terragrunt/.mise.toml) |
| `talosctl` | Talos cluster access and config import | [`terragrunt/.mise.toml`](../terragrunt/.mise.toml) |
| `sops`, `age` | Encrypt and decrypt the `*.sops.yaml` secrets ([`architecture/secrets.md`](architecture/secrets.md)) | [`.mise.toml`](../.mise.toml) |
| `op` (1Password CLI) | Resolve `op://` references during bootstrap | [`.mise.toml`](../.mise.toml) |
| `just`, `gum` | Command runner and its prompts and logging for `just bootstrap::cluster` | [`.mise.toml`](../.mise.toml) |
| `helm`, `helmfile` | Install foundational CRDs and infra before Flux ([`k8s/bootstrap/README.md`](../k8s/bootstrap/README.md)) | [`.mise.toml`](../.mise.toml) |
| `kubectl`, `jq`, `yq`, `minijinja` | Cluster access and the templating and JSON/YAML processing the bootstrap and scripts use | [`.mise.toml`](../.mise.toml) |
| `kustomize`, `kubeconform` | Render and validate the manifests locally, as CI does | [`k8s/.mise.toml`](../k8s/.mise.toml) |
| `flate`, `pre-commit`, `lychee`, `kind` | Run CI checks locally: Flux validation, hooks, docs link check, bootstrap test cluster ([`architecture/ci.md`](architecture/ci.md)) | [`.mise.toml`](../.mise.toml) |
| [`direnv`](https://direnv.net/) | Load each environment's `.envrc` (state role) when entering its folder | not pinned, see [`terragrunt/README.md`](../terragrunt/README.md#prerequisites) |

### Access

Besides the tools you need the access listed under [Terragrunt prerequisites](../terragrunt/README.md#prerequisites) (SOPS age key, AWS credentials for the state role, network access to the Proxmox API) and the [bootstrap prerequisites](../k8s/bootstrap/README.md#deploying-infrastructure-and-applications) (a signed-in 1Password CLI).

**Expected result:** the pinned tools are installed, and Terragrunt can decrypt the SOPS files and assume the environment's state role. Without the age key, values silently fall back to CI placeholders and a real plan fails.

This page does not cover what has to exist outside the repo first: the Proxmox hosts, the network, the 1Password vault and the AWS remote-state setup (its bootstrapping doc is not written yet, see the [architecture index](architecture/README.md#index)). A hardware summary is deliberately left out until the disclosure question in [#1601](https://github.com/isejalabs/homelab/issues/1601) is decided.

## 1. Choose an environment

Read what each environment is for in [`architecture/environments.md`](architecture/environments.md#what-each-environment-is-for) and pick one of `dbg`, `dev`, `head`, `poc`, `prod`, `qa`, `rebuild`, `src`.

**Expected result:** you know the environment name used by every later step, and which app set Flux will deploy there (minimal or full, see "Minimal / optional" in the [glossary](glossary.md)). `prod` and `qa` may only be applied from `main`.

## 2. Provision the VMs and install Talos

Follow [plan and apply a unit](../terragrunt/README.md#plan-and-apply-a-unit) for the environment's `vehagn-k8s` unit.

**Expected result:** the Proxmox VMs exist and a Talos-managed Kubernetes control plane and nodes are up, with nothing running on them yet (see [`architecture/overview.md`](architecture/overview.md#infrastructure-proxmox--talos--kubernetes)). A successful apply is not yet proof that the cluster is usable; the next step is the real check.

## 3. Get cluster access and check the nodes

Merge the `talosconfig` and generate the `kubeconfig` as described in [import configs](../terragrunt/README.md#import-configs), then run the [preliminary checks](../k8s/bootstrap/README.md#preliminary-checks).

**Expected result:** a kube context for the environment exists, all nodes are `Ready`, and no pod is in the `Failed` phase.

## 4. Bootstrap foundational services and hand off to Flux

Follow [cluster deployment with `just` (and Flux CD)](../k8s/bootstrap/README.md#cluster-deployment-with-just-and-flux-cd). The install order is in [`architecture/workloads.md`](architecture/workloads.md#bootstrap-install-order).

**Expected result:** the foundational CRDs and infra (Cilium, sealed-secrets, cert-manager, external-secrets, 1Password Connect, the Flux operator and instance) are installed, and Flux takes over. Every `Kustomization` then reaches `READY=True` within a few reconcile intervals ([how long that takes per environment](architecture/environments.md#2-how-updates-land)); the [Flux section](../k8s/bootstrap/README.md#flux-cd) of the bootstrap doc has the check. One that stays `False` needs resolving first, see [`troubleshooting-flux.md`](troubleshooting/troubleshooting-flux.md).

## 5. Check the app data

Apps that use the repo's storage components are populated by kopiur when their volumes are created, see [restore-on-create](backup/kopiur-backup-restore.md#restore-on-create-the-core-idea). Nothing to run unless a check fails.

**Expected result:** on a first deploy, apps start with empty volumes; when backups exist for the environment, each app's data is present, not just its PVC `Bound`. If a `proxmox-csi`-pinned volume was kept, confirm it is bound again as described in [step 5 of the rebuild guide](backup/disaster-recovery.md#5-re-attach-any-proxmox-csi-pinned-volumes).

## 6. Final end-to-end check

Run the checks in [step 6 of the rebuild guide](backup/disaster-recovery.md#6-final-end-to-end-check).

**Expected result:** all `Kustomization`s and `HelmRelease`s are ready and none is suspended, no unexpected non-running pods, monitoring works for the new cluster, and at least one user-facing app works end to end.

## Where to go next

- Day-to-day operations are in [`docs/README.md`](README.md#finding-what-you-need).
- Upgrading or replacing nodes: [`node-lifecycle.md`](operations/node-lifecycle.md).
- Tearing a cluster down again: [Cluster end of lifecycle](../terragrunt/README.md#cluster-end-of-lifecycle).
