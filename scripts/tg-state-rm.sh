#!/bin/sh

# remove state of proxmox volumes to prevent their deletion by a `tofu/terragrunt destroy` command
# this allows re-using them upon re-creating the cluster (needs state import then)
for i in $(terragrunt state list | grep module.volumes.module.proxmox-volume); do terragrunt state rm "$i"; done

# also remove everything which would block a destroy command when the cluster is not functional or nodes shut down
terragrunt state rm 'module.sealed_secrets.kubernetes_namespace.sealed-secrets'
terragrunt state rm 'module.sealed_secrets.kubernetes_secret.sealed-secrets-key'
terragrunt state rm 'module.talos.talos_cluster_kubeconfig.this'
terragrunt state rm 'module.talos.talos_machine_secrets.this'
terragrunt state rm 'module.talos.talos_image_factory_schematic.updated'
terragrunt state rm 'module.talos.talos_image_factory_schematic.this'
terragrunt state rm 'module.proxmox_csi_plugin.kubernetes_secret.proxmox-csi-plugin'
terragrunt state rm 'module.proxmox_csi_plugin.kubernetes_namespace.csi-proxmox'
terragrunt state rm 'module.talos.talos_machine_bootstrap.this'
