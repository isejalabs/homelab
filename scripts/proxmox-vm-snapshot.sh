#!/bin/bash
# Creates a Proxmox snapshot named <name> (default "initial") on every VM belonging to <env>, in parallel,
# via the Proxmox REST API -- no SSH. The "Snapshot" half of #1296's one-go workflow. Non-destructive
# (additive only) -- no confirmation prompt. See docs/proxmox-vm-snapshots.md.
#
# Usage: scripts/proxmox-vm-snapshot.sh -e <env> [--name <name>]
set -euo pipefail

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"
. "${SCRIPTS_DIR}/lib/proxmox.sh"

usage() {
    echo "Usage: $(basename "$0") -e <env> [--name <name>]" >&2
    exit 1
}

ENV=""
NAME="initial"
while [ $# -gt 0 ]; do
    case "$1" in
        -e | --environment)
            ENV="$2"
            shift 2
            ;;
        --name)
            NAME="$2"
            shift 2
            ;;
        -h | --help) usage ;;
        -*) unknown_flag "$1" ;;
        *) usage ;;
    esac
done

[ -z "${ENV}" ] && usage
validate_environment "${ENV}"
proxmox_validate_snapshot_name "${NAME}"
proxmox_load_secrets

VMS=$(proxmox_discover_vms "${ENV}")
if [ -z "${VMS}" ]; then
    log fatal "no VMs found for environment" "env" "${ENV}"
    exit 1
fi

# Fails fast, before touching anything, if any VM already carries a snapshot of this name -- never
# silently overwrites a snapshot something else (e.g. a later rollback) might already depend on.
EXISTING=()
while IFS=$'\t' read -r vmid node name _status; do
    [ -z "${vmid}" ] && continue
    snapshots=$(proxmox_curl GET "/nodes/${node}/qemu/${vmid}/snapshot") || exit 1
    if jq -e --arg n "${NAME}" 'any(.[]; .name == $n)' <<<"${snapshots}" >/dev/null; then
        EXISTING+=("${vmid} (${name})")
    fi
done <<<"${VMS}"

if [ "${#EXISTING[@]}" -gt 0 ]; then
    log fatal "snapshot '${NAME}' already exists on some VMs -- pick a different --name or remove it first" "vms" "${EXISTING[*]}"
    exit 1
fi

log info "Creating snapshot on all ${ENV} VMs" "name" "${NAME}"

# A ZFS/PVE snapshot is a fast metadata-only operation, so running every VM's snapshot creation in
# parallel (PID-array pattern copied from scripts/kopiur-create.sh's --all path) is low-risk here -- unlike
# rollback's stop+rollback+start(+boot) cycle, there's no meaningful per-node resource contention to worry
# about.
snapshot_one() {
    local vmid="$1" node="$2" name="$3"
    log info "creating snapshot" "vmid" "${vmid}" "name" "${name}" "node" "${node}"
    local upid
    upid=$(proxmox_curl POST "/nodes/${node}/qemu/${vmid}/snapshot" "snapname=${NAME}") || return 1
    proxmox_wait_task "${node}" "${upid}"
}

PIDS=()
KEYS=()
while IFS=$'\t' read -r vmid node name _status; do
    [ -z "${vmid}" ] && continue
    snapshot_one "${vmid}" "${node}" "${name}" &
    PIDS+=($!)
    KEYS+=("${vmid} (${name})")
done <<<"${VMS}"

FAILED=()
for i in "${!PIDS[@]}"; do
    if ! wait "${PIDS[$i]}"; then
        FAILED+=("${KEYS[$i]}")
    fi
done

if [ "${#FAILED[@]}" -gt 0 ]; then
    log error "failed to snapshot some VMs" "vms" "${FAILED[*]}"
    exit 1
fi

log info "Snapshot created on all ${ENV} VMs." "name" "${NAME}"
