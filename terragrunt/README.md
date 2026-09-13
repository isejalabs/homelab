See [`docs/architecture/secrets.md`](../docs/architecture/secrets.md) for how SOPS secrets feed into
Terragrunt (the `*-secrets.sops.yaml` hierarchy consumed by `root.hcl`).

# Folder Structure

Structure is `terragrunt/<non-prod|prod>/<account>/<region>/<env>/<module>`. `root.hcl` merges
`account.hcl`/`region.hcl`/`env.hcl` locals and SOPS-encrypted `*-secrets.sops.yaml` at each level
(global → account → region → env → local, each overriding the last), and wires the S3 remote-state backend.

```
📁 terragrunt
├── root.hcl                       # top-level config, see above
├── global-secrets.sops.yaml       # secrets merged in at every level
├── 📁 _envcommon                    # reusable .hcl includes merged into each module's live config (see _envcommon/README.md)
│   ├── tf-state-read-role.hcl
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
```

> **TODO** document more

# RustFS buckets/users for kopiur backup

`rustfs-kopiur-backup` provisions, per environment, a RustFS bucket, a policy scoped to it, and a dedicated
user via [`rustfs-bucket-user`](https://github.com/isejalabs/terraform-modules/tree/main/modules/rustfs-bucket-user),
and writes the resulting credentials (plus a generated `KOPIA_PASSWORD`) into a `kopiur-backup#<env>`
1Password item via [`onepassword-item`](https://github.com/isejalabs/terraform-modules/tree/main/modules/onepassword-item)
-- see [`rustfs-kopiur-backup`'s README](https://github.com/isejalabs/terraform-modules/tree/main/modules/rustfs-kopiur-backup)
for the full mechanism and current caveats. Requires both a `rustfs` and an `onepassword` entry in
`global-secrets.sops.yaml`.

Units exist for all 8 environments. Only `dev`/`qa`/`rebuild`/`prod` have an active kopiur backup schedule
on the Kubernetes side (see `isejalabs/homelab#1121`); `dbg`/`head`/`poc`/`src` still get a real bucket and
1Password item so their `ClusterRepository` has something valid to connect to, but nothing writes to it on
a schedule.

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

Once cluster is up, import its configs.

### talosconfig
```sh
talosctl config merge .terragrunt-cache/**/output/talos-config.yaml
```

### kubeconfig

```sh
talosctl kubeconfig -n 10.7.8.131
```

Another hacky method:

```sh
cp ~/.kube/config ~/.kube/config.bak && KUBECONFIG=~/.kube/config:output/kube-config.yaml kubectl config view --flatten > /tmp/config && mv /tmp/config ~/.kube/config
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
