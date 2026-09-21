#!/bin/bash
# Lists the Proxmox VMs belonging to one environment (discovered via scripts/lib/proxmox.sh's
# 70081<id><n> vmid scheme, cross-checked against each VM's name prefix) and each VM's snapshots, via the
# Proxmox REST API -- no SSH. Read-only. See docs/proxmox-vm-snapshots.md.
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
    printf 'VMID\tNAME\tNODE\tSTATUS\tSNAPSHOT\tTAKEN_AT\n'
    while IFS=$'\t' read -r vmid node name status; do
        [ -z "${vmid}" ] && continue
        snapshots=$(proxmox_curl GET "/nodes/${node}/qemu/${vmid}/snapshot") || continue
        rows=$(jq -r '.[] | select(.name != "current") | [.name, (.snaptime // empty)] | @tsv' <<<"${snapshots}")
        if [ -z "${rows}" ]; then
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${vmid}" "${name}" "${node}" "${status}" "-" "-"
            continue
        fi
        while IFS=$'\t' read -r snapname snaptime; do
            taken_at="-"
            if [ -n "${snaptime}" ]; then
                # BSD/macOS `date -r <epoch>` vs GNU `date -d @<epoch>` -- the former errors on GNU date
                # (where -r means "use this file's mtime", and no such file exists), so the fallback covers
                # Linux/CI without misinterpreting the epoch as a filename there.
                taken_at=$(date -r "${snaptime}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@${snaptime}" '+%Y-%m-%d %H:%M:%S')
            fi
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${vmid}" "${name}" "${node}" "${status}" "${snapname}" "${taken_at}"
        done <<<"${rows}"
    done <<<"${VMS}"
} | column -t -s $'\t'
