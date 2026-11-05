#!/bin/sh
# Removes from Terragrunt state every resource that would otherwise block `terragrunt destroy` when the
# cluster is unreachable (nodes shut down, or already gone) - resources whose provider needs to actually
# talk to a live Kubernetes API to compute a destroy plan (in-cluster k8s_* resources, and Talos resources
# that depend on node connectivity). This only forgets them from state; it never deletes the real objects,
# so it's meant for a cluster that's being torn down anyway, not a live one.
#
# Usage: scripts/tg-state-rm.sh
# Run from the terragrunt unit directory whose state should be pruned (same convention as a bare
# `terragrunt state rm`/`terragrunt destroy`) - not from the repo root.

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

# module.volumes.module.persistent-volume.* covers a variable number of per-app persistent-volume submodules
# (one per app-owned volume), so these are discovered via `state list` rather than named individually below.
for i in $(terragrunt state list | grep module.volumes.module.persistent-volume); do
    log info "removing from state" "resource" "$i"
    terragrunt state rm "$i"
done
log info "removing from state" "resource" "module.sealed_secrets.kubernetes_namespace.sealed-secrets"
terragrunt state rm 'module.sealed_secrets.kubernetes_namespace.sealed-secrets'
log info "removing from state" "resource" "module.sealed_secrets.kubernetes_secret.sealed-secrets-key"
terragrunt state rm 'module.sealed_secrets.kubernetes_secret.sealed-secrets-key'
log info "removing from state" "resource" "module.talos.talos_cluster_kubeconfig.this"
terragrunt state rm 'module.talos.talos_cluster_kubeconfig.this'
log info "removing from state" "resource" "module.talos.talos_machine_secrets.this"
terragrunt state rm 'module.talos.talos_machine_secrets.this'
log info "removing from state" "resource" "module.talos.talos_image_factory_schematic.updated"
terragrunt state rm 'module.talos.talos_image_factory_schematic.updated'
log info "removing from state" "resource" "module.talos.talos_image_factory_schematic.this"
terragrunt state rm 'module.talos.talos_image_factory_schematic.this'
log info "removing from state" "resource" "module.proxmox_csi_plugin.kubernetes_secret.proxmox-csi-plugin"
terragrunt state rm 'module.proxmox_csi_plugin.kubernetes_secret.proxmox-csi-plugin'
log info "removing from state" "resource" "module.proxmox_csi_plugin.kubernetes_namespace.csi-proxmox"
terragrunt state rm 'module.proxmox_csi_plugin.kubernetes_namespace.csi-proxmox'
log info "removing from state" "resource" "module.talos.talos_machine_bootstrap.this"
terragrunt state rm 'module.talos.talos_machine_bootstrap.this'
