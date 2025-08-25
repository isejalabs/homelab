#!/bin/sh

terragrunt state rm 'module.proxmox_csi_plugin.kubernetes_secret.proxmox-csi-plugin'
terragrunt state rm 'module.proxmox_csi_plugin.kubernetes_namespace.csi-proxmox'
terragrunt state rm 'module.volumes.module.persistent-volume["pv-mongodb"].kubernetes_persistent_volume.pv'
terragrunt state rm 'module.volumes.module.proxmox-volume["pv-mongodb"].restapi_object.proxmox-volume'
terragrunt state rm 'module.sealed_secrets.kubernetes_namespace.sealed-secrets'
terragrunt state rm 'module.sealed_secrets.kubernetes_secret.sealed-secrets-key'
terragrunt state rm 'module.talos.talos_cluster_kubeconfig.this'
terragrunt state rm 'module.talos.talos_machine_bootstrap.this'
terragrunt state rm 'module.talos.talos_machine_secrets.this'
terragrunt state rm 'module.talos.talos_image_factory_schematic.updated'
terragrunt state rm 'module.talos.talos_image_factory_schematic.this'

#terragrunt state rm 'module.talos.talos_machine_configuration_apply.this["dbg-ctrl-01.test.iseja.net"]''
#terragrunt state rm 'module.talos.talos_machine_configuration_apply.this["dbg-work-02.test.iseja.net"]'
