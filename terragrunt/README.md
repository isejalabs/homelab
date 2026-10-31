# Terragrunt

OpenTofu/Terragrunt configuration for everything this repo provisions outside the Kubernetes cluster: the Proxmox VMs and the Talos install of each cluster, and the out-of-cluster pieces around it — Terraform state access roles in AWS, RustFS buckets and users, 1Password items, Checkmk monitoring objects, and Keycloak realms. What runs *inside* a cluster is reconciled by Flux from [`k8s/`](../k8s/README.md) instead, after [`k8s/bootstrap`](../k8s/bootstrap/README.md) has handed off to it.

This folder holds only the *live* configuration (which module, which version, which inputs, per environment). The modules themselves live in other repositories: [`isejalabs/terraform-proxmox-talos`](https://github.com/isejalabs/terraform-proxmox-talos) for the cluster, [`isejalabs/terraform-modules`](https://github.com/isejalabs/terraform-modules) for everything else, and [`cisagov/terraform-state-read-role-tf-module`](https://github.com/cisagov/terraform-state-read-role-tf-module) for the state roles. See [`docs/architecture/repositories.md`](../docs/architecture/repositories.md) for which repo and tool owns what, [ADR 0002](../docs/decisions/0002-opentofu-vs-terraform.md)/[ADR 0003](../docs/decisions/0003-terragrunt.md) for why OpenTofu and Terragrunt, and [`docs/architecture/secrets.md`](../docs/architecture/secrets.md) for how the SOPS secrets below feed in.

**Common tasks:** [plan/apply a unit](#plan-and-apply-a-unit) · [reconnect cluster access after bootstrap](#cluster-bootstrap) · [import a Proxmox volume](#import-proxmox-volume) · [clean up state or destroy a cluster](#cluster-end-of-lifecycle) · [snapshot or power-cycle VMs](#proxmox-vm-snapshots-and-power) · [rebuild a whole cluster](../docs/backup/disaster-recovery.md#full-cluster-rebuild).

**On this page:** [Prerequisites](#prerequisites) · [Folder structure](#folder-structure) · [Units](#units) · [Plan and apply a unit](#plan-and-apply-a-unit) · [Provider lock files](#provider-lock-files) · [Cluster (`vehagn-k8s`)](#cluster-vehagn-k8s) · [`poc`-only units](#poc-only-units-vms-talos-proxmox) · [State access role](#state-access-role-tf-state-read-role) · [RustFS buckets/users](#rustfs-bucketsusers-rustfs-kopiur-backup-rustfs-keycloak-db) · [RustFS monitoring identity](#rustfs-monitoring-identity) · [Keycloak realms](#keycloak-realms-keycloak-realm) · [Checkmk configuration](#checkmk-configuration)

## Prerequisites

- **Tools**: `opentofu`, `terragrunt` and `talosctl` are pinned in [`.mise.toml`](.mise.toml) next to this README; `sops`/`age`, the 1Password CLI `op` and `kubectl` come from the repo root's [`.mise.toml`](../.mise.toml). `mise install` in the repo root and in this folder installs them. [direnv](https://direnv.net/) loads each environment's `.envrc` (see [Plan and apply a unit](#plan-and-apply-a-unit)).
- **SOPS age key**: every unit decrypts the `*-secrets.sops.yaml` files (see below); without the key, values fall back to CI placeholders and a real plan fails.
- **AWS credentials** allowed to assume the environment's state role (`TG_IAM_ASSUME_ROLE`), for the S3/DynamoDB remote state.
- **Per unit**: network access to whatever the unit manages — the Proxmox API for `vehagn-k8s`, RustFS and 1Password for the `rustfs-*` units, the Checkmk site for `checkmk-*`, Keycloak for `keycloak-realm`. The prerequisites specific to one unit are in its section below.

## Folder structure

Structure is `terragrunt/<non-prod|prod>/<account>/<region>/<env>/<unit>`. `root.hcl` merges `account.hcl`/`region.hcl`/`env.hcl` locals and SOPS-encrypted `*-secrets.sops.yaml` at each level (global → account → region → env → local, each overriding the last), and wires the S3 remote-state backend.

```
📁 terragrunt
├── root.hcl                       # top-level config, see above
├── global-secrets.sops.yaml       # secrets merged in at every level (Proxmox, RustFS, 1Password, Checkmk, ...)
├── global.hcl                     # non-secret values shared by all environments/units (e.g. 1Password vault ID)
├── .mise.toml                     # opentofu/terragrunt/talosctl versions
├── 📁 _envcommon                    # one <unit>.hcl per unit type, included by every environment's copy of that unit
│   ├── checkmk-longhorn-monitoring.hcl
│   ├── checkmk-password.hcl
│   ├── checkmk-rustfs-monitoring.hcl
│   ├── keycloak-realm.hcl
│   ├── rustfs-bucket-reader.hcl
│   ├── rustfs-keycloak-db.hcl
│   ├── rustfs-kopiur-backup.hcl
│   ├── talos-proxmox.hcl            # poc only
│   ├── tf-state-read-role.hcl
│   ├── vehagn-k8s.hcl
│   ├── 📁 vehagn-k8s                # shared Talos machine-config patches
│   └── vms.hcl                      # poc only
├── 📁 non-prod                      # account: dbg, dev, head, poc, qa, rebuild, src environments
│   ├── account.hcl
│   ├── account-secrets.sops.yaml
│   └── 📁 eu-central-1                # region
│       ├── region.hcl
│       └── 📁 <env>                   # env, e.g. dev, qa, rebuild, ...
│           ├── env.hcl
│           ├── .envrc                   # exports TG_IAM_ASSUME_ROLE, the env's state-read/write role (direnv-loaded)
│           ├── 📁 <unit>                # one folder per unit, see Units below
│           │   └── terragrunt.hcl
│           └── 📁 vehagn-k8s
│               ├── terragrunt.hcl
│               └── 📁 assets            # generated cluster artifacts (Talos schematic, sealed-secrets cert, ...)
└── 📁 prod                          # account: prod environment only, same account/region/env/unit shape as non-prod
```

### How a unit's configuration is assembled

A unit's `terragrunt.hcl` is deliberately thin. It includes `root.hcl` (remote state, the merged secrets, the account/region/env locals) and `_envcommon/<unit>.hcl` (the module source and the inputs shared by all environments), and adds only what differs for its environment — see [the Terragrunt documentation](https://terragrunt.gruntwork.io/docs/features/keep-your-terragrunt-architecture-dry/) for the pattern. So to change a value for every environment, edit `_envcommon/<unit>.hcl`; to change it for one, edit that environment's `terragrunt.hcl`.

Module versions follow the environments' roles ([`docs/architecture/environments.md`](../docs/architecture/environments.md)): most units pin a release tag (in `_envcommon/<unit>.hcl`, or in the unit itself for `vehagn-k8s`), `head` tracks the module's latest commit (`?ref=HEAD`), and `src` uses a local checkout next to this repo (`../terraform-proxmox-talos`, `../terraform-modules`) to test module changes before they are released.

## Units

| Unit | Provisions | Module | Environments | Details |
| --- | --- | --- | --- | --- |
| `vehagn-k8s` | the cluster: Proxmox VMs, Talos install and bootstrap, sealed-secrets key, proxmox-csi credentials, Proxmox volumes | `terraform-proxmox-talos` | all 8 | [Cluster](#cluster-vehagn-k8s) |
| `tf-state-read-role` | the environment's IAM role for its Terraform state | `cisagov/terraform-state-read-role-tf-module` | all 8 | [State access role](#state-access-role-tf-state-read-role) |
| `rustfs-kopiur-backup` | RustFS bucket + user for kopiur app backups, `kopiur-backup#<env>` 1Password item | `rustfs-kopiur-backup` | all 8 | [RustFS buckets/users](#rustfs-bucketsusers-rustfs-kopiur-backup-rustfs-keycloak-db) |
| `rustfs-keycloak-db` | RustFS bucket + user for the Keycloak database backup, `keycloak-db#<env>` 1Password item | `rustfs-kopiur-backup` | `dev`, `qa`, `rebuild`, `prod` | [RustFS buckets/users](#rustfs-bucketsusers-rustfs-kopiur-backup-rustfs-keycloak-db) |
| `rustfs-bucket-reader` | read-only RustFS identity for capacity monitoring, `checkmk-monitoring#<env>` 1Password item | `rustfs-bucket-reader` | all 8 | [RustFS monitoring identity](#rustfs-monitoring-identity) |
| `checkmk-password` | Checkmk Password Store entry for that identity | `checkmk-password` | all 8 | [Password Store entries](#password-store-entries-checkmk-password) |
| `checkmk-rustfs-monitoring` | Checkmk hosts and rules for RustFS quota monitoring | `checkmk-rustfs-monitoring` | `prod` only (one shared unit) | [Host and rules](#host-and-rules-checkmk-rustfs-monitoring) |
| `checkmk-longhorn-monitoring` | Checkmk hosts and rules for Longhorn capacity monitoring | `checkmk-longhorn-monitoring` | `prod` only (one shared unit) | [Longhorn capacity](#longhorn-capacity-checkmk-longhorn-monitoring) |
| `keycloak-realm` | Keycloak realms, LDAP federation to UCS, `groups` scope | `keycloak-realm` | `dev`, `qa` | [Keycloak realms](#keycloak-realms-keycloak-realm) |
| `vms`, `talos-proxmox` | experimental standalone VMs / Talos cluster | `vms`, `talos-proxmox` | `poc` only | [`poc`-only units](#poc-only-units-vms-talos-proxmox) |

Modules without an owner prefix are in [`isejalabs/terraform-modules`](https://github.com/isejalabs/terraform-modules/tree/main/modules); each has its own README with the full mechanism. Every unit has its own state, so units are planned and applied one at a time; where one needs another (e.g. `checkmk-password` needs `rustfs-bucket-reader`), the order is stated in its section.

## Plan and apply a unit

From the unit's directory, here the cluster unit of `prod` — the environment most likely to actually need this during a disaster recovery:

```sh
cd terragrunt/prod/eu-central-1/prod/vehagn-k8s   # generic: terragrunt/<account>/<region>/<env>/<unit>
terragrunt plan
terragrunt apply
```

Each environment directory has an `.envrc` (e.g. `terragrunt/prod/eu-central-1/prod/.envrc`) that exports `TG_IAM_ASSUME_ROLE`, the per-env state-read/write role Terragrunt assumes for the S3 remote-state backend. The first time you `cd` into a given environment's directory, direnv blocks until you approve its content once:

```sh
direnv allow
```

After that one-time approval, every later `cd` into that same directory auto-loads it via the normal direnv shell hook -- no need to repeat it, and no need to touch `.envrc` directly. Only in a context with no direnv hook at all (a script, a non-interactive shell) does that hook never fire, in which case `source .envrc` directly instead, or every command fails with a generic S3 `HeadObject`/`403 Forbidden` on state access (easy to misdiagnose as an unrelated AWS credentials problem).

**Apply from `main`, not a feature branch.** `prod` and `qa` may *only* ever be applied from a `main` checkout. The one exception is a staged, node-by-node Talos/Kubernetes version upgrade, whose steps may be applied from one dedicated upgrade branch (see [`docs/operations/node-lifecycle.md`](../docs/operations/node-lifecycle.md#staging-a-multi-step-upgrade-on-one-branch)). For the other environments, applying from a feature branch to validate a not-yet-merged change is acceptable, but merge it promptly afterward so the next `main` apply is a no-op — there's no one-command revert for a Terragrunt apply the way there is for Flux config, since it creates real state that only matches that unmerged branch.

A unit that fails on state access or a lock: see [`docs/troubleshooting/troubleshooting-terraform-state.md`](../docs/troubleshooting/troubleshooting-terraform-state.md). For how the cluster apply fits into a full rebuild, see [`docs/backup/disaster-recovery.md`](../docs/backup/disaster-recovery.md).

## Provider lock files

The provider versions of a unit are pinned by its `.terraform.lock.hcl`, next to the unit's `terragrunt.hcl`. They are tracked in git for the **`prod` and `qa`** units; for every other environment `.gitignore` ignores them (`terragrunt/non-prod/**/.*.lock.hcl`, except `qa`). Without a lock file every fresh `init` takes the newest provider version the module allows, so a `prod` apply could silently use a different provider than the one tested in the pull request.

**Create the lock file in the pull request that adds or changes a `prod`/`qa` unit,** not by the apply: `prod` and `qa` are applied by hand from `main` after the merge, and a lock file created only then ends up as an untracked file in the applying checkout and never gets committed. A committed lock is also validated by CI, and the apply from `main` then finds it and does not create or change a file.

```sh
cd terragrunt/<account>/<region>/<env>/<unit>   # e.g. terragrunt/prod/eu-central-1/prod/checkmk-password
terragrunt run --non-interactive -- init -backend=false -input=false
terragrunt run --non-interactive -- providers lock -platform=darwin_arm64 -platform=linux_amd64
git add .terraform.lock.hcl
```

The second command adds the hashes for macOS on Apple silicon and Linux on amd64 (the platforms of the maintainer's machine and of CI) to the lock; it does not change a locked version. It needs no cloud credentials. To move to newer providers, run the first command with `-upgrade` and commit the result. To check that a lock is complete, run `init -backend=false -lockfile=readonly`: it fails instead of changing the file.

CI enforces this: `scripts/terragrunt-validate-all.sh` fails for a `prod` or `qa` unit without a committed lock file and runs `init` on those units with `-lockfile=readonly`, so a lock that lacks a provider, or the hashes for CI's platform, fails the check instead of being extended on the fly. To check a unit the way CI does: `scripts/terragrunt-validate-all.sh terragrunt/prod/eu-central-1/prod/<unit>`.

If an apply leaves a modified or untracked `.terraform.lock.hcl` behind anyway (a provider version or hash that was not in the committed file), commit it through a pull request like any other change. A leftover untracked copy that is identical to a newly committed lock has to be deleted before pulling, as git does not overwrite untracked files.

## Cluster (`vehagn-k8s`)

The `vehagn-k8s` unit of each environment creates the whole cluster from [`isejalabs/terraform-proxmox-talos`](https://github.com/isejalabs/terraform-proxmox-talos): the Proxmox VMs, the Talos machine configuration and bootstrap, the `sealed-secrets-bootstrap-key` and the proxmox-csi credentials inside the new cluster, and the Proxmox volumes for persistent data. Sizing, node placement and Talos/Kubernetes versions are the unit's inputs; per-environment values are in [`docs/reference/environments.md`](../docs/reference/environments.md), version upgrades and node changes in [`docs/operations/node-lifecycle.md`](../docs/operations/node-lifecycle.md). After the apply, [`k8s/bootstrap`](../k8s/bootstrap/README.md) installs the foundational services and hands off to Flux.

### Sealed-secrets key files in a fresh checkout

A fresh checkout/worktree is missing a file every `vehagn-k8s` plan/apply needs, and it isn't tracked in git. The module's `bootstrap/sealed-secrets` submodule unconditionally reads `assets/sealed-secrets/certificate/{sealed-secrets.cert,sealed-secrets.key}` relative to the environment's own `vehagn-k8s/` directory (Terragrunt copies local files alongside the fetched remote module source into the same working dir, so this resolves against the *per-environment* `assets/` folder shown in the [folder structure](#folder-structure) above, not the vendored module repo). Those two files are generated once and live only in that gitignored folder of whichever checkout generated them -- a different checkout or a disposable worktree doesn't have them, and any `plan`/`apply` then fails with `Invalid value for "path" parameter: no file exists at "./assets/sealed-secrets/certificate/sealed-secrets.cert"`. Scope the command with `-target='module.talos'` to skip evaluating `module.sealed_secrets` entirely rather than generating a new keypair -- a different keypair than what's already live breaks every existing `SealedSecret` in the cluster, since this module provisions the cert/key pair as the live `sealed-secrets-bootstrap-key` TLS secret.

### Cluster bootstrap

#### Remove existing contexts from config

Delete exising talosconfig and kubeconfig cluster entries (otherwise new config would get suffixed with `-1`)

```sh
CLUSTER="dev-homelab"; talosctl config remove ${CLUSTER}; kubectl config delete-context admin@${CLUSTER}; kubectl config delete-user admin@${CLUSTER}; kubectl config delete-cluster ${CLUSTER}
```

#### Import configs

Once cluster is up, import its configs. Both come from `local_file` resources the `vehagn-k8s` module's own `output.tf` writes during `terragrunt apply` (`talos-config.yaml`, `kube-config.yaml`, and others) into an `output/` directory relative to wherever Terraform actually ran. Since Terragrunt copies the module into a per-run cache directory first, that's `.terragrunt-cache/<hash1>/<hash2>/output/`, not a plain `output/` next to this README -- and since the two hash segments change across cache invalidations, the commands below use a `**` glob to find the directory rather than a fixed path.

##### talosconfig
```sh
talosctl config merge .terragrunt-cache/**/output/talos-config.yaml
```

##### kubeconfig

```sh
talosctl kubeconfig -n 10.7.8.130
```

`10.7.8.130` is the cluster's own VIP, `10.7.8.1<id>0` -- substitute `<id>` for the target environment (e.g. `10.7.8.180` for `prod`, `id=8`); see [`docs/reference/environments.md#environment-id`](../docs/reference/environments.md#environment-id) for the full table. Querying the VIP rather than a specific node means this works regardless of which node is currently up.

If the VIP isn't reachable yet (or you specifically want the kubeconfig Terraform generated, rather than a fresh one fetched live via the Talos API), extract it from the Terragrunt output instead. Resolve the cache path into a variable first, rather than using the `**` glob directly on the right-hand side of the `KUBECONFIG=` assignment -- a glob pattern there isn't expanded the way it is in a normal command argument position:

```sh
OUTPUT_DIR=$(ls -d .terragrunt-cache/**/output)
cp ~/.kube/config ~/.kube/config.bak
KUBECONFIG=~/.kube/config:"$OUTPUT_DIR"/kube-config.yaml kubectl config view --flatten > /tmp/config && mv /tmp/config ~/.kube/config
```

Second hacky alternative, a symlink instead of a variable -- same root cause/fix, just inlined into one line:

```sh
ln -s .terragrunt-cache/**/output output.workaround; cp ~/.kube/config ~/.kube/config.bak; KUBECONFIG=~/.kube/config:output.workaround/kube-config.yaml kubectl config view --flatten > /tmp/config && mv /tmp/config ~/.kube/config; rm output.workaround
```

### Proxmox volume handling

#### Import Proxmox volume

Import Proxmox volume into state without the need to recreate it (e.g. for recovery purpose where data was kept from a previous cluster).

The following command imports the PV `pv-mongodb` residing on PVE node `pve4` in the `dev` environment (with environment-specific prefix `9813-dev`):

```sh
terragrunt import 'module.volumes.module.proxmox-volume["pv-mongodb"].restapi_object.proxmox-volume' /api2/json/nodes/pve4/storage/local-enc/content/local-enc:vm-9813-dev-pv-mongodb
terragrunt import 'module.volumes.module.persistent-volume["pv-mongodb"].kubernetes_persistent_volume.pv' pv-mongodb
```

Before destroying the previous cluster, its volumes' state has to be removed to keep them out of the `destroy`, cf. [how to prevent deletion of Proxmox volumes](#prevent-deletion-of-proxmox-volumes).

#### Prevent deletion of Proxmox volumes

```sh
for i in $(terragrunt state list | grep module.volumes.module.proxmox-volume); do terragrunt state rm "$i"; done
```

The script [`scripts/tg-state-rm.sh`](../scripts/tg-state-rm.sh) does the job by keeping all Proxmox volumes and shortcutting the cluster destruction.

### Cluster end of lifecycle

#### Delete dangling states

Needed because of e.g. problematic `module.talos.data.talos_cluster_health.this`.  Also helps when destroying a cluster that is shut down.

```sh
terragrunt state rm 'module.sealed_secrets.kubernetes_namespace.sealed-secrets'
terragrunt state rm 'module.sealed_secrets.kubernetes_secret.sealed-secrets-key'
terragrunt state rm 'module.talos.talos_cluster_kubeconfig.this'
terragrunt state rm 'module.talos.talos_machine_secrets.this'
terragrunt state rm 'module.talos.talos_image_factory_schematic.updated'
terragrunt state rm 'module.talos.talos_image_factory_schematic.this'
terragrunt state rm 'module.proxmox_csi_plugin.kubernetes_secret.proxmox-csi-plugin'
terragrunt state rm 'module.proxmox_csi_plugin.kubernetes_namespace.csi-proxmox'
terragrunt state rm 'module.talos.talos_machine_bootstrap.this'
```

The script [`scripts/tg-state-rm.sh`](../scripts/tg-state-rm.sh) does the job by keeping all Proxmox volumes and shortcutting the cluster destruction by deleting the states mentioned above.

#### Destroy a cluster

##### Keep data needed afterwards

Before destroying a cluster, ensure data is backed up or PV data is kept by e.g. [preventing deletion of Proxmox volumes](#prevent-deletion-of-proxmox-volumes).

##### Destroy problematic cluster

Destroy a cluster without refreshing states, e.g. when its problematic (state cannot be refreshed) or when state refresh would harm (e.g. re-add proxmox volumes):

```sh
terragrunt plan -destroy -refresh=false -out _out && terragrunt apply _out
```

### Proxmox VM snapshots and power

Snapshots and power actions for all VMs of an environment are `just` recipes that use the Proxmox REST API, no SSH to the nodes: `just proxmox::snapshot::*` (see [`docs/operations/proxmox-vm-snapshots.md`](../docs/operations/proxmox-vm-snapshots.md)) and `just proxmox::vm::*` (see [`docs/operations/proxmox-vm-power.md`](../docs/operations/proxmox-vm-power.md)), e.g.

```sh
just proxmox::snapshot::create -e dev --name initial
```

Fallback without `just`, on the Proxmox node that hosts the VMs (`qm` only sees local VMs): the cluster VMs have IDs `70081<env-id><n>` ([env IDs](../docs/reference/environments.md#environment-id); here `dev`, ID 3, nodes 1–5):

```sh
j=700813; for i in {5..1}; do echo -n "processing VM $j$i "; qm snapshot $j$i wip --vmstate 1; echo "done"; done
```

## `poc`-only units (`vms`, `talos-proxmox`)

`poc` additionally has two standalone units next to its `vehagn-k8s`: `vms` (plain Proxmox VMs, from the `vms` module) and `talos-proxmox` (a separate Talos cluster, from the `talos-proxmox` module), for ad hoc experiments beyond the standard cluster module (see `poc` in [`docs/architecture/environments.md`](../docs/architecture/environments.md)). They are pinned to early module versions and not part of any regular procedure; don't copy them to another environment as a template.

## State access role (`tf-state-read-role`)

Each environment's `tf-state-read-role` unit creates the IAM role that the environment's `.envrc` exports as `TG_IAM_ASSUME_ROLE` (e.g. `dev-non-prod-homelab-eu-central-1-tf-state-<account-id>-RW-Role`). Despite the module's name the role is read/write (`read_only = false`), scoped to that environment's state objects (`<account>/<region>/<env>/*/tf.tfstate*`) in the account's state bucket. Creating the role and the state bucket for a new environment before any state exists is the bootstrapping problem tracked in [#195](https://github.com/isejalabs/homelab/issues/195).

## RustFS buckets/users (`rustfs-kopiur-backup`, `rustfs-keycloak-db`)

`rustfs-kopiur-backup` provisions, per environment, a RustFS bucket, a policy scoped to it, and a dedicated user via [`rustfs-bucket-user`](https://github.com/isejalabs/terraform-modules/tree/main/modules/rustfs-bucket-user), and writes the resulting credentials (plus a generated `KOPIA_PASSWORD`) into a `kopiur-backup#<env>` 1Password item via [`onepassword-item`](https://github.com/isejalabs/terraform-modules/tree/main/modules/onepassword-item) -- see [`rustfs-kopiur-backup`'s README](https://github.com/isejalabs/terraform-modules/tree/main/modules/rustfs-kopiur-backup) for the full mechanism and current caveats. Requires both a `rustfs` and an `onepassword` entry in `global-secrets.sops.yaml`.

Units exist for all 8 environments. Only `dev`/`qa`/`rebuild`/`prod` have an active kopiur backup schedule on the Kubernetes side (see [isejalabs/homelab#1121](https://github.com/isejalabs/homelab/issues/1121)); `dbg`/`head`/`poc`/`src` still get a real bucket and 1Password item so their `ClusterRepository` has something valid to connect to, but nothing writes to it on a schedule.

`rustfs-keycloak-db` reuses the same module with `name = "keycloak-db"` to give the Keycloak CloudNativePG cluster its own bucket and scoped user (`<env>-keycloak-db`) and a `keycloak-db#<env>` 1Password item (its extra `KOPIA_PASSWORD` field is unused). Units exist for `dev`, `qa`, `rebuild` and `prod`; only `dev` has been applied so far, `qa` and `prod` are applied from `main` as usual. See [isejalabs/homelab#1826](https://github.com/isejalabs/homelab/issues/1826).

## RustFS monitoring identity

`rustfs-bucket-reader` provisions, per environment, a read-only RustFS identity for capacity monitoring via [`rustfs-bucket-reader`](https://github.com/isejalabs/terraform-modules/tree/main/modules/rustfs-bucket-reader): a `<env>-checkmk-monitoring` user whose policy allows only the bucket-scoped `s3:GetBucketQuota` action on that environment's own buckets (`<env>-kopiur-backup`, plus `<env>-longhorn-backup` for `dev`/`qa`/`rebuild`/`prod`). It creates no buckets or quotas and grants no object, listing or admin access. The generated access key and secret are written into a `checkmk-monitoring#<env>` item in the `K8S` 1Password vault, following that vault's `<thing>#<env>` item naming (the RustFS-side user and policy are `<env>-checkmk-monitoring`) (shared with `rustfs-kopiur-backup` via [`global.hcl`](global.hcl)); no credential is a module output. Requires both a `rustfs` and an `onepassword` entry in `global-secrets.sops.yaml`, like `rustfs-kopiur-backup`. See the module's README for the full mechanism and caveats.

Units exist for all 8 environments, even though all identities are consumed by the one Checkmk `prod` site, so each environment owns its own user and can be created, rotated or removed on its own. Like for kopiur, `head` tracks the module's latest commit instead of a pinned release tag, and `src` uses a local checkout of `terraform-modules`.

Using a created identity is a separate, manual step: copy its access key and secret from 1Password into the Checkmk `prod` site's Password Store (never into command-line arguments of the special-agent call, which are visible in process listings). To roll back, remove that Password Store entry first, then destroy the environment's `rustfs-bucket-reader` unit, which removes the RustFS user and policy and the managed 1Password item.

### Verifying a RustFS monitoring identity

After applying a `rustfs-bucket-reader` unit (and again after a RustFS upgrade, a module change, or when Checkmk reports UNKNOWN), check that the identity reads quota of its own buckets and nothing else:

```sh
scripts/rustfs-verify-monitoring.sh -e <env>
```

It reads the endpoint from `terragrunt/global-secrets.sops.yaml` and the identity's credentials from the `checkmk-monitoring#<env>` 1Password item, then runs only non-mutating requests: quota-stats on each own bucket must return 200, while quota-stats on another environment's bucket, object listing, `GetObject`/`DeleteObject` of a random non-existent key and the admin `info`/`scanner/status` routes must all return 403. It exits non-zero and shows the response body on any deviation. Not for CI: it needs 1Password and network access to the RustFS.

Pitfalls it already accounts for, in case you query by hand:

- `op read` and `op://` references cannot address these items: the secret reference syntax rejects the `#` in `checkmk-monitoring#<env>`. Use `op item get 'checkmk-monitoring#<env>' --vault K8S --fields label=ACCESS_KEY --reveal`.
- A trailing slash in the endpoint turns requests into `//<path>`, which RustFS answers with a misleading `InvalidBucketName`.
- `ListBuckets` (`GET /`) returned a 500 (`errBucketMetadataNotInitialized`) instead of a 403 on RustFS 1.0.0-beta.12 (not rechecked on 1.0.1); it is not one of the checks, and monitoring never calls it.
- Pass credentials to curl on stdin (`-K -`), not as arguments, so they stay out of the process list.

## Keycloak realms (`keycloak-realm`)

`keycloak-realm` fills a running Keycloak with its realm content (`iseja`, `admin`, each with a read-only LDAP federation to UCS and a `groups` claim scope) through the module `keycloak-realm` from `isejalabs/terraform-modules`, pinned to a release tag. Units exist for `dev` and `qa`; the directory facts and realm definitions are shared in `_envcommon/keycloak-realm.hcl`, only the Keycloak URL differs per environment. The unit is proven in `dev`, then copied to `qa` and `prod` through a pull request and applied from `main`; prerequisites (UCS groups and bind account, 1Password items, CA trust) are in [`docs/identity/keycloak-realms.md`](../docs/identity/keycloak-realms.md).

## Checkmk configuration

The Checkmk site is configured as code with the community provider `registry.terraform.io/blackmesaltd/checkmk` (not in the OpenTofu registry, hence the full address; pinned exactly in the module) -- see [ADR 0015](../docs/decisions/0015-checkmk-configuration-as-code.md) for the decision, the options reviewed and the spike results.

### Password Store entries (`checkmk-password`)

The per-environment `checkmk-password` unit reads the secret key from the environment's `checkmk-monitoring#<env>` 1Password item (written by the `rustfs-bucket-reader` unit above) and stores it as Password Store entry `<env>_checkmk_monitoring` via [`checkmk-password`](https://github.com/isejalabs/terraform-modules/tree/main/modules/checkmk-password). Checkmk rules reference the entry by that identifier, so no secret is carried inline. Units exist for all 8 environments; a unit can only be applied once the environment's `rustfs-bucket-reader` identity exists. `head` tracks the module's latest commit and `src` uses a local checkout, like the other units.

The provider authenticates as the Checkmk automation user `terraform` through the `checkmk` entry (`url`, `username`, `secret`) in `global-secrets.sops.yaml`; `url` is the site URL including the site name, without a trailing slash (for example `https://monitoring2.home.iseja.net/prod`). A Password Store entry needs no activation, and the provider never activates implicitly. The secret is held in the Terraform state like the other secrets managed here. The user needs no administrator rights, only a dedicated role with 14 permissions; how to create it is in [`docs/operations/checkmk-automation-user.md`](../docs/operations/checkmk-automation-user.md).

Rollback: remove or edit any rule that references the entry first, then destroy the environment's `checkmk-password` unit (this removes the Password Store entry only; the RustFS identity and the 1Password item are untouched).

### Host and rules (`checkmk-rustfs-monitoring`)

One shared unit, `prod/eu-central-1/prod/checkmk-rustfs-monitoring`, creates the Checkmk side of the RustFS quota monitoring through [`checkmk-rustfs-monitoring`](https://github.com/isejalabs/terraform-modules/tree/main/modules/checkmk-rustfs-monitoring): one dedicated API-only host per RustFS monitoring identity (`rustfs-dev.fiona.home.iseja.net`, `rustfs-qa…`, `rustfs-prod…`) in the folder `/misc` (the folder must exist; not a VM folder such as `/container/pve4`, whose inherited settings like "expect piggyback data" do not suit API-only hosts), each with its own special-agent rule, and an activation.

**Moving the hosts to another folder.** The provider never changes the folder of an existing host (its update only sends attributes), so changing `folder` in the unit alone would only change the state, not Checkmk, and every later plan would show the difference again. Move the hosts in Checkmk first (GUI "Move to folder", or the REST `move` action; the host name stays, so services, history and RRD data are kept), activate, and only then change `folder` in the unit: the plan from `main` must show no changes.

**Why one host per identity:** Checkmk runs only the *first* matching rule of the special-agent ruleset per host (found on the real site: with three rules on one host, `cmk -D` showed a single agent call and discovery found only the `qa-` buckets), so each identity needs its own host. **Why hosts of their own at all:** `fiona.home.iseja.net` already exists (in `/container/pve4`) with the normal Checkmk agent, and a special-agent rule on a host with the normal agent *replaces* its agent connection (verified: Checkmk then generates only the special-agent program and no TCP connection), which would silence its existing checks. The new hosts have no IP address and no agent, only the special agent.

**The `rules_enabled` switch.** The special-agent rules use the ruleset `special_agents:rustfs_quota`, which is defined by the plugin package ([`rustfs_quota`](https://github.com/isejalabs/checkmk-modules/tree/main/packages/rustfs_quota) in `checkmk-modules`), not by Checkmk itself. Checkmk rejects a rule for a ruleset it does not know ("The ruleset of name 'special_agents:rustfs_quota' is not known"), so applying the rules before the plugin is installed on the site fails. `rules_enabled` in the unit (default `false`) lets everything else be applied first: the host, the polling interval and the activation are created either way. To turn the rules on: install the released plugin on the site (through Salt), set `rules_enabled = true` in the unit, apply. The reverse order matters as well: set it back to `false` and apply *before* removing the plugin, otherwise Checkmk no longer shows the existing rules and Terraform fails trying to recreate them. The rules follow a fixed contract (`endpoint`, `access_key`, `secret_key` as a Password Store reference, `buckets`; see the module README) that the plugin implements. They reference the Password Store entries created by the `checkmk-password` units, so apply those first. Which environments get a rule is the `identity_envs` list in `_envcommon/checkmk-rustfs-monitoring.hcl`: add an environment once its `rustfs-bucket-reader` and `checkmk-password` units are applied. Which environments have a Longhorn backup bucket is stated once in [`global.hcl`](global.hcl).

**Polling interval.** Checkmk fetches a host's data and checks all its services once per check interval, one minute by default, and each run makes one request per bucket (RustFS logs every one as a warning-level event). The unit sets `check_interval_minutes = 15` through a rule on each API-only host, which covers its bucket services and the service that runs the special agent. This was verified in the generated Nagios configuration of a Checkmk Raw site (`check_interval 15.0`).

**Activation never forces other people's changes.** The unit activates the pending changes after each change of the host or the rules, but with `force_foreign_changes = false`: if someone else has pending changes in the Checkmk UI, the apply fails with "Activation Failed ... status 401" and activates nothing (this module's own changes stay pending). Resolve the other pending changes in Checkmk (activate or discard them), then run the apply again.

Enabling the rules later: install the plugin on the site, set `rules_enabled = true` in the unit, and apply. Rollback: destroy the unit (removes the rules and the host; the Password Store entries and the RustFS identities are untouched), or set `rules_enabled = false` to remove only the rules. Do not edit the host in the Checkmk UI: the provider replaces a host's attributes as a whole, so Terraform would reset it.

### Longhorn capacity (`checkmk-longhorn-monitoring`)

One shared unit, `prod/eu-central-1/prod/checkmk-longhorn-monitoring`, creates the Checkmk side of the Longhorn disk-capacity monitoring through [`checkmk-longhorn-monitoring`](https://github.com/isejalabs/terraform-modules/tree/main/modules/checkmk-longhorn-monitoring): one dedicated API-only host per monitored environment, named after its real Longhorn hostname, in the per-environment folder `/K8S/envs/<env>` (the folders must exist), each with its own special-agent rule. The special agent reads Longhorn's unauthenticated `/v1/*` API through the environment's existing Longhorn UI route, so no credential is involved.

- **Which environments**: the `monitored_envs` list in [`_envcommon/checkmk-longhorn-monitoring.hcl`](_envcommon/checkmk-longhorn-monitoring.hcl) (`dev`, `qa`, `prod` so far). The on-demand environments are left out on purpose: their Longhorn would be polled while stopped. Add an environment once it has been verified.
- **No host check**: the hosts have no address (`address_family = "no-ip"`), because ICMP to a Cilium gateway VIP is not answered and kept the `dev`/`qa` hosts DOWN ([#1926](https://github.com/isejalabs/homelab/issues/1926)).
- **Polling interval**: five minutes (`check_interval_minutes = 5`).
- **`rules_enabled`**: same switch and same ordering rule as for [`checkmk-rustfs-monitoring`](#host-and-rules-checkmk-rustfs-monitoring), here for the `longhorn_capacity` plugin package from `checkmk-modules`; it is `true` because the plugin is installed on the site.
