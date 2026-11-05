#!/bin/sh
# Removes every Proxmox-volume resource from Terragrunt state, so a subsequent `terragrunt destroy` leaves
# the real Proxmox disks in place instead of deleting them - meant for tearing down a cluster while
# preserving its data volumes for reuse when the cluster is re-created (at which point they need
# `terragrunt import`ing back into state, since Terragrunt no longer knows about them).
#
# Usage: scripts/volume-remove-state.sh
# Run from the terragrunt unit directory whose state should be pruned (same convention as a bare
# `terragrunt state rm`) - not from the repo root.

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

# module.volumes.module.proxmox-volume.* covers a variable number of per-app volume submodules (one per
# app-owned Proxmox disk), so these are discovered via `state list` rather than named individually.
for i in $(terragrunt state list | grep module.volumes.module.proxmox-volume); do
    log info "removing from state" "resource" "$i"
    terragrunt state rm "$i"
done
