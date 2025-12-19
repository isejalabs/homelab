# Directory handling

```sh
cd terragrunt/<account>/<region>/<env>/vehagn-k8s
```

> **TODO** document more

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
