#!/bin/bash
# Lists the Proxmox VMs belonging to one environment (discovered via scripts/lib/proxmox.sh's
# 70081<id><n> vmid scheme, cross-checked against each VM's name prefix), via the Proxmox REST API -- no
# SSH. Read-only. VM-only view, no snapshot detail -- see scripts/proxmox-snapshot-list.sh for that. See
# docs/proxmox-vm-power.md.
#
# Usage: scripts/proxmox-vm-list.sh -e <env>
set -euo pipefail

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"
. "${SCRIPTS_DIR}/lib/proxmox.sh"

usage() {
    echo "Usage: $(basename "$0") -e <env>" >&2
    exit 1
}

ENV=""
while [ $# -gt 0 ]; do
    case "$1" in
        -e | --environment)
            ENV="$2"
            shift 2
            ;;
        -h | --help) usage ;;
        -*) unknown_flag "$1" ;;
        *) usage ;;
    esac
done

[ -z "${ENV}" ] && usage
validate_environment "${ENV}"
proxmox_load_secrets

VMS=$(proxmox_discover_vms "${ENV}")
if [ -z "${VMS}" ]; then
    log fatal "no VMs found for environment" "env" "${ENV}"
    exit 1
fi

{
    printf 'VMID\tNAME\tNODE\tSTATUS\n'
    printf '%s\n' "${VMS}" | awk -F'\t' -v OFS='\t' '{print $1, $3, $2, $4}'
} | column -t -s $'\t'
