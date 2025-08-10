```shell
cd terragrunt/<account>/<region>/<env>/vehagn-k8s

# delete exising talosconfig cluster config (otherwise new config would be suffixed with "-1")
CLUSTER="dev-vehagn-tg"; talosctl config remove ${CLUSTER}

# import talosconfig
talosctl config merge output/talos-config.yaml

# delete exising kubeconfig cluster config (otherwise new config would be suffixed with "-1")
CLUSTER="dev-vehagn-tg"; kubectl config delete-context admin@${CLUSTER}; kubectl config delete-user admin@${CLUSTER}; kubectl config delete-cluster ${CLUSTER}

cp ~/.kube/config ~/.kube/config.bak && KUBECONFIG=~/.kube/config:output/kube-config.yaml kubectl config view --flatten > /tmp/config && mv /tmp/config ~/.kube/config
```

## import Proxmox Volume

```sh
terragrunt import 'module.volumes.module.proxmox-volume["pv-mongodb"].restapi_object.proxmox-volume' /api2/json/nodes/pve4/storage/local-enc/content/local-enc:vm-9815-src-pv-mongodb
terragrunt import 'module.volumes.module.persistent-volume["pv-mongodb"].kubernetes_persistent_volume.pv' pv-mongodb
```

## Delete dangling states

Needed because of e.g. problematic `module.talos.data.talos_cluster_health.this`

```sh
terragrunt state rm 'module.proxmox_csi_plugin.kubernetes_secret.proxmox-csi-plugin'
terragrunt state rm 'module.proxmox_csi_plugin.kubernetes_namespace.csi-proxmox'
terragrunt state rm 'module.volumes.module.persistent-volume["pv-mongodb"].kubernetes_persistent_volume.pv'
terragrunt state rm 'module.volumes.module.proxmox-volume["pv-mongodb"].restapi_object.proxmox-volume'
terragrunt state rm 'module.sealed_secrets.kubernetes_namespace.sealed-secrets'
terragrunt state rm 'module.sealed_secrets.kubernetes_secret.sealed-secrets-key'

terragrunt state rm 'module.talos.proxmox_virtual_environment_vm.this["src-work-02.test.iseja.net"]'
terragrunt state rm 'module.talos.proxmox_virtual_environment_vm.this["src-ctrl-01.test.iseja.net"]'
```
