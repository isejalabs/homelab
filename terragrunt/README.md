See [`docs/architecture/secrets.md`](../docs/architecture/secrets.md) for how SOPS secrets feed into Terragrunt (the `*-secrets.sops.yaml` hierarchy consumed by `root.hcl`).

# Folder Structure

Structure is `terragrunt/<non-prod|prod>/<account>/<region>/<env>/<module>`. `root.hcl` merges `account.hcl`/`region.hcl`/`env.hcl` locals and SOPS-encrypted `*-secrets.sops.yaml` at each level (global → account → region → env → local, each overriding the last), and wires the S3 remote-state backend.

```
📁 terragrunt
├── root.hcl                       # top-level config, see above
├── global-secrets.sops.yaml       # secrets merged in at every level
├── global.hcl                     # non-secret values shared by all environments/components (e.g. 1Password vault ID)
├── 📁 _envcommon                    # reusable .hcl includes merged into each module's live config (see _envcommon/README.md)
│   ├── tf-state-read-role.hcl
│   ├── rustfs-bucket-reader.hcl
│   ├── rustfs-bucket-reader.hcl
│   ├── vms.hcl
│   ├── talos-proxmox.hcl
│   └── vehagn-k8s.hcl
├── 📁 non-prod                      # account: dbg, dev, head, poc, qa, rebuild, src environments
│   ├── account.hcl
│   ├── account-secrets.sops.yaml
│   └── 📁 eu-central-1                # region
│       ├── region.hcl
│       └── 📁 <env>                   # env, e.g. dev, qa, rebuild, ... (poc additionally splits vms/talos-proxmox out of vehagn-k8s)
│           ├── env.hcl
│           ├── .envrc                   # exports TG_IAM_ASSUME_ROLE, the env's state-read/write role (direnv-loaded)
│           ├── 📁 tf-state-read-role      # module: per-env state-read IAM role
│           └── 📁 vehagn-k8s              # module: provisions the Proxmox VMs and installs Talos
│               ├── terragrunt.hcl
│               └── 📁 assets                # generated cluster artifacts (Talos schematic, sealed-secrets cert, ...)
└── 📁 prod                          # account: prod environment only, same account/region/env/module shape as non-prod
```

# Directory handling

```sh
cd terragrunt/<account>/<region>/<env>/vehagn-k8s
terragrunt plan
terragrunt apply
```

Concretely, for `prod` -- the environment most likely to actually need this during a disaster recovery, where you want the exact commands ready to run without first mentally substituting placeholders:

```sh
cd terragrunt/prod/eu-central-1/prod/vehagn-k8s
terragrunt plan
terragrunt apply
```

Each environment directory has an `.envrc` (e.g. `terragrunt/prod/eu-central-1/prod/.envrc`) that exports `TG_IAM_ASSUME_ROLE`, the per-env state-read/write role Terragrunt assumes for the S3 remote-state backend. The first time you `cd` into a given environment's directory, direnv blocks until you approve its content once:

```sh
direnv allow
```

After that one-time approval, every later `cd` into that same directory auto-loads it via the normal direnv shell hook -- no need to repeat it, and no need to touch `.envrc` directly. Only in a context with no direnv hook at all (a script, a non-interactive shell) does that hook never fire, in which case `source .envrc` directly instead, or every command fails with a generic S3 `HeadObject`/`403 Forbidden` on state access (easy to misdiagnose as an unrelated AWS credentials problem).

**Apply from `main`, not a feature branch.** `prod` and `qa` may *only* ever be applied from a `main` checkout — no exceptions. For the other environments, applying from a feature branch to validate a not-yet-merged change is acceptable, but merge it promptly afterward so the next `main` apply is a no-op — there's no one-command revert for a Terragrunt apply the way there is for Flux config, since it creates real state that only matches that unmerged branch.

See [`docs/disaster-recovery.md`](../docs/disaster-recovery.md) for how this step fits into a full cluster rebuild.

# RustFS buckets/users for kopiur backup

`rustfs-kopiur-backup` provisions, per environment, a RustFS bucket, a policy scoped to it, and a dedicated user via [`rustfs-bucket-user`](https://github.com/isejalabs/terraform-modules/tree/main/modules/rustfs-bucket-user), and writes the resulting credentials (plus a generated `KOPIA_PASSWORD`) into a `kopiur-backup#<env>` 1Password item via [`onepassword-item`](https://github.com/isejalabs/terraform-modules/tree/main/modules/onepassword-item) -- see [`rustfs-kopiur-backup`'s README](https://github.com/isejalabs/terraform-modules/tree/main/modules/rustfs-kopiur-backup) for the full mechanism and current caveats. Requires both a `rustfs` and an `onepassword` entry in `global-secrets.sops.yaml`.

Units exist for all 8 environments. Only `dev`/`qa`/`rebuild`/`prod` have an active kopiur backup schedule on the Kubernetes side (see [isejalabs/homelab#1121](https://github.com/isejalabs/homelab/issues/1121)); `dbg`/`head`/`poc`/`src` still get a real bucket and 1Password item so their `ClusterRepository` has something valid to connect to, but nothing writes to it on a schedule.

# RustFS monitoring identity

`rustfs-bucket-reader` provisions, per environment, a read-only RustFS identity for capacity monitoring via [`rustfs-bucket-reader`](https://github.com/isejalabs/terraform-modules/tree/main/modules/rustfs-bucket-reader): a `<env>-checkmk-monitoring` user whose policy allows only the bucket-scoped `s3:GetBucketQuota` action on that environment's own buckets (`<env>-kopiur-backup`, plus `<env>-longhorn-backup` for `dev`/`qa`/`rebuild`/`prod`). It creates no buckets or quotas and grants no object, listing or admin access. The generated access key and secret are written into a `checkmk-monitoring#<env>` item in the `K8S` 1Password vault, following that vault's `<thing>#<env>` item naming (the RustFS-side user and policy are `<env>-checkmk-monitoring`) (shared with `rustfs-kopiur-backup` via [`global.hcl`](global.hcl)); no credential is a module output. Requires both a `rustfs` and an `onepassword` entry in `global-secrets.sops.yaml`, like `rustfs-kopiur-backup`. See the module's README for the full mechanism and caveats.

Units exist for all 8 environments, even though all identities are consumed by the one Checkmk `prod` site, so each environment owns its own user and can be created, rotated or removed on its own. Like for kopiur, `head` tracks the module's latest commit instead of a pinned release tag, and `src` uses a local checkout of `terraform-modules`.

Using a created identity is a separate, manual step: copy its access key and secret from 1Password into the Checkmk `prod` site's Password Store (never into command-line arguments of the special-agent call, which are visible in process listings). To roll back, remove that Password Store entry first, then destroy the environment's `rustfs-bucket-reader` unit, which removes the RustFS user and policy and the managed 1Password item.

## Verifying a RustFS monitoring identity

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

# Checkmk configuration

The Checkmk site is configured as code with the community provider `registry.terraform.io/blackmesaltd/checkmk` (not in the OpenTofu registry, hence the full address; pinned exactly in the module) -- see [ADR 0015](../docs/decisions/0015-checkmk-configuration-as-code.md) for the decision, the options reviewed and the spike results.

## Password Store entries (`checkmk-password`)

The per-environment `checkmk-password` unit reads the secret key from the environment's `checkmk-monitoring#<env>` 1Password item (written by the `rustfs-bucket-reader` unit above) and stores it as Password Store entry `<env>_checkmk_monitoring` via [`checkmk-password`](https://github.com/isejalabs/terraform-modules/tree/main/modules/checkmk-password). Checkmk rules reference the entry by that identifier, so no secret is carried inline. Units exist for all 8 environments; a unit can only be applied once the environment's `rustfs-bucket-reader` identity exists. `head` tracks the module's latest commit and `src` uses a local checkout, like the other units.

The provider authenticates as the Checkmk automation user `terraform` through the `checkmk` entry (`url`, `username`, `secret`) in `global-secrets.sops.yaml`; `url` is the site URL including the site name, without a trailing slash (for example `https://monitoring2.home.iseja.net/prod`). A Password Store entry needs no activation, and the provider never activates implicitly. The secret is held in the Terraform state like the other secrets managed here.

Rollback: remove or edit any rule that references the entry first, then destroy the environment's `checkmk-password` unit (this removes the Password Store entry only; the RustFS identity and the 1Password item are untouched).

## Host and rules (`checkmk-rustfs-monitoring`)

One shared unit, `prod/eu-central-1/prod/checkmk-rustfs-monitoring`, creates the Checkmk side of the RustFS quota monitoring through [`checkmk-rustfs-monitoring`](https://github.com/isejalabs/terraform-modules/tree/main/modules/checkmk-rustfs-monitoring): a dedicated API-only host `rustfs.fiona.home.iseja.net` in the folder `/container/pve4` (the folder must exist), one special-agent rule per RustFS monitoring identity, and an activation.

**Why a host of its own:** `fiona.home.iseja.net` already exists in that folder with the normal Checkmk agent, and a special-agent rule on a host with the normal agent *replaces* its agent connection (verified: Checkmk then generates only the special-agent program and no TCP connection), which would silence its existing checks. The new host has no IP address and no agent, only the special agents.

**Rules are off until the plugin exists.** `rules_enabled` in the unit is `false`: the ruleset `special_agents:rustfs_quota` is defined by the RustFS quota special-agent plugin, which has to be installed on the Checkmk site first (through Salt), and Checkmk rejects a rule for a ruleset it does not know. Until then the unit creates only the host. The rules follow a fixed contract (`endpoint`, `access_key`, `secret_key` as a Password Store reference, `buckets`; see the module README) that the plugin has to implement. They reference the Password Store entries created by the `checkmk-password` units, so apply those first. Which environments get a rule is the `identity_envs` list in `_envcommon/checkmk-rustfs-monitoring.hcl`: add an environment once its `rustfs-bucket-reader` and `checkmk-password` units are applied. Which environments have a Longhorn backup bucket is stated once in [`global.hcl`](global.hcl).

**Activation never forces other people's changes.** The unit activates the pending changes after each change of the host or the rules, but with `force_foreign_changes = false`: if someone else has pending changes in the Checkmk UI, the apply fails with "Activation Failed ... status 401" and activates nothing (this module's own changes stay pending). Resolve the other pending changes in Checkmk (activate or discard them), then run the apply again.

Enabling the rules later: install the plugin on the site, set `rules_enabled = true` in the unit, and apply. Rollback: destroy the unit (removes the rules and the host; the Password Store entries and the RustFS identities are untouched), or set `rules_enabled = false` to remove only the rules. Do not edit the host in the Checkmk UI: the provider replaces a host's attributes as a whole, so Terraform would reset it.

## The automation user's role

`terraform` does not need to be an administrator. Create a role from the built-in `no_permissions` role with exactly the 14 permissions the Checkmk modules need, and give it to the user. This was verified against a Checkmk Raw 2.4 site: with only this role the provider applied, re-planned without changes and destroyed everything the spike created. (A role cloned from `user` also works but carries about 370 inherited permissions, including 16 more Setup ones, so do not use it.) Use an existing Checkmk admin account for these calls and read its secret without echoing it:

```sh
CMK='https://<checkmk-host>/<site>/check_mk/api/1.0'   # no trailing slash
read -rs ADMIN_SECRET                                  # paste the admin user's secret, press Enter
AUTH="Authorization: Bearer <admin-username> $ADMIN_SECRET"

# 1. Create the role from no_permissions
curl -sS -X POST -H "$AUTH" -H 'Content-Type: application/json' \
  "$CMK/domain-types/user_role/collections/all" \
  -d '{"role_id":"no_permissions","new_role_id":"tf_auto","new_alias":"Terraform automation"}'

# 2. Grant exactly these 14 permissions
curl -sS -X PUT -H "$AUTH" -H 'Content-Type: application/json' \
  "$CMK/objects/user_role/tf_auto" \
  -d '{"new_permissions":{"general.use":"yes","wato.use":"yes","wato.edit":"yes","wato.passwords":"yes","wato.edit_all_passwords":"yes","wato.edit_hosts":"yes","wato.manage_hosts":"yes","wato.edit_folders":"yes","wato.manage_folders":"yes","wato.all_folders":"yes","wato.see_all_folders":"yes","wato.rulesets":"yes","wato.activate":"yes","wato.activateforeign":"yes"}}'

# 3. Give the existing `terraform` automation user that role (a PUT needs the object's ETag in If-Match)
ETAG=$(curl -sS -D - -o /dev/null -H "$AUTH" "$CMK/objects/user_config/terraform" | tr -d '\r' | awk -F': ' 'tolower($1)=="etag"{print $2}')
curl -sS -X PUT -H "$AUTH" -H 'Content-Type: application/json' -H "If-Match: $ETAG" \
  "$CMK/objects/user_config/terraform" -d '{"roles":["tf_auto"]}'
```

Check with `GET $CMK/objects/user_role/tf_auto`: `extensions.permissions` must list exactly those 14. Step 1 fails if the role exists already; step 2 can be repeated. The same can be done in the UI (Setup > Users > Roles: clone **No permissions**, enable the same permissions, then set the user's role).

# Proxmox volume handling

## Import Proxmox volume

Import Proxmox volume into state without the need to recreate it (e.g. for recovery purpose where data was kept from a previous cluster).

The following command imports the PV `pv-mongodb` residing on PVE node `pve4` in the `dev` environment (with environment-specific prefix `9813-dev`):

```sh
terragrunt import 'module.volumes.module.proxmox-volume["pv-mongodb"].restapi_object.proxmox-volume' /api2/json/nodes/pve4/storage/local-enc/content/local-enc:vm-9813-dev-pv-mongodb
terragrunt import 'module.volumes.module.persistent-volume["pv-mongodb"].kubernetes_persistent_volume.pv' pv-mongodb
```

Previously, one needs to remove the volumes' state to exclude them from a `detroy` command, cf. [how to prevent deletion of Proxmox volumes](#prevent-deletion-of-proxmox-volumes).

## Prevent deletion of Proxmox volumes

```sh
for i in $(terragrunt state list | grep module.volumes.module.proxmox-volume); do terragrunt state rm "$i"; done
```

The script [`scripts/tg-state-rm.sh`](../scripts/tg-state-rm.sh) does the job by keeping all Proxmox volumes and shortcutting the cluster destruction.

# Cluster bootstrap

## Remove existing contexts from config

Delete exising talosconfig and kubeconfig cluster entries (otherwise new config would get suffixed with `-1`)

```sh
CLUSTER="dev-homelab"; talosctl config remove ${CLUSTER}; kubectl config delete-context admin@${CLUSTER}; kubectl config delete-user admin@${CLUSTER}; kubectl config delete-cluster ${CLUSTER}
```

## Import configs

Once cluster is up, import its configs. Both come from `local_file` resources the `vehagn-k8s` module's own `output.tf` writes during `terragrunt apply` (`talos-config.yaml`, `kube-config.yaml`, and others) into an `output/` directory relative to wherever Terraform actually ran. Since Terragrunt copies the module into a per-run cache directory first, that's `.terragrunt-cache/<hash1>/<hash2>/output/`, not a plain `output/` next to this README -- and since the two hash segments change across cache invalidations, the commands below use a `**` glob to find the directory rather than a fixed path.

### talosconfig
```sh
talosctl config merge .terragrunt-cache/**/output/talos-config.yaml
```

### kubeconfig

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

# Cluster end of lifecycle


## Delete dangling states

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

## Destroy a cluster

### Keep data needed afterwards

Before destroying a cluster, ensure data is backed up or PV data is kept by e.g. [preventing deletion of Proxmox volumes](#prevent-deletion-of-proxmox-volumes).

### Destroy problematic cluster

Destroy a cluster without refreshing states, e.g. when its problematic (state cannot be refreshed) or when state refresh would harm (e.g. re-add proxmox volumes):

```sh
terragrunt plan -destroy -refresh=false -out _out && terragrunt apply _out
```

# Proxmox VMs

## Snapshot

```
j=700813; for i in {5..1}; do echo -n "processing VM $j$i "; qm snapshot $j$i wip --vmstate 1; echo "done"; done
```
