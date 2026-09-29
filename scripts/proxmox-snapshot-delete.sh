#!/bin/bash
# Deletes a named snapshot from every VM belonging to <env>, or just one with --vmid, via the Proxmox
# REST API -- no SSH. See docs/proxmox-vm-snapshots.md.
#
# Destructive and irreversible, though lower-stakes than rollback -- this only discards the snapshot
# itself, never any live VM state. Requires typed confirmation unless -y/--yes or --vmid is given, same
# rule as proxmox-vm-power.sh's stop/shutdown/reset: a single --vmid target already makes the blast radius
# explicit.
#
# Unlike create/rollback, this doesn't require every discovered VM to agree on snapshot presence -- some
# VMs having the snapshot and others not is a normal, expected state (e.g. a snapshot taken before a node
# joined the environment), so this deletes it wherever it exists and reports, rather than fails, wherever
# it doesn't.
#
# Proxmox does not restrict snapshot deletion to only the most recent snapshot (unlike rollback) --
# deleting a snapshot merges its data forward as needed regardless of chain position; confirmed both via
# the Proxmox API docs (the only documented parameter is `force`, for config/disk-state divergence, not
# chain position) and live during this feature's own testing (see docs/proxmox-vm-snapshots.md).
#
# Usage: scripts/proxmox-snapshot-delete.sh -e <env> [--name <name>] [--vmid <vmid>] [-y|--yes]
set -euo pipefail

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"
. "${SCRIPTS_DIR}/lib/proxmox.sh"

usage() {
    echo "Usage: $(basename "$0") -e <env> [--name <name>] [--vmid <vmid>] [-y|--yes]" >&2
    exit 1
}

ENV=""
NAME="initial"
VMID=""
YES=0
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
        --vmid)
            VMID="$2"
            shift 2
            ;;
        -y | --yes)
            YES=1
            shift
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
VMS=$(printf '%s\n' "${VMS}" | proxmox_filter_vmid "${VMID}")

# Partition into "has this snapshot" / "doesn't" up front, as parallel arrays -- only the former are
# actually touched, the latter are just reported so the operator knows the batch wasn't fully uniform,
# never silently ignored.
DELETE_VMID=()
DELETE_NODE=()
DELETE_NAME=()
SKIPPED=()
while IFS=$'\t' read -r vmid node name _status; do
    [ -z "${vmid}" ] && continue
    snapshots=$(proxmox_curl GET "/nodes/${node}/qemu/${vmid}/snapshot") || exit 1
    if jq -e --arg n "${NAME}" 'any(.[]; .name == $n)' <<<"${snapshots}" >/dev/null; then
        DELETE_VMID+=("${vmid}")
        DELETE_NODE+=("${node}")
        DELETE_NAME+=("${name}")
    else
        SKIPPED+=("${vmid} (${name})")
    fi
done <<<"${VMS}"

if [ "${#DELETE_VMID[@]}" -eq 0 ]; then
    log fatal "snapshot '${NAME}' doesn't exist on any selected VM" "env" "${ENV}"
    exit 1
fi

if [ "${#SKIPPED[@]}" -gt 0 ]; then
    log warn "snapshot '${NAME}' doesn't exist on some VMs -- skipping those, deleting only where present" "skipped" "${SKIPPED[*]}"
fi

if [ -z "${VMID}" ] && [ "${YES}" -eq 0 ]; then
    log info "About to delete snapshot '${NAME}' from the following ${ENV} VMs:" "env" "${ENV}"
    {
        printf 'VMID\tNAME\tNODE\n'
        for i in "${!DELETE_VMID[@]}"; do
            printf '%s\t%s\t%s\n' "${DELETE_VMID[$i]}" "${DELETE_NAME[$i]}" "${DELETE_NODE[$i]}"
        done
    } | column -t -s $'\t'

    printf 'Type the environment name (%s) to confirm deleting snapshot %s: ' "${ENV}" "${NAME}"
    read -r CONFIRM
    if [ "${CONFIRM}" != "${ENV}" ]; then
        log fatal "confirmation did not match -- aborting"
        exit 1
    fi
fi

# Deletes snapshot $NAME from a single VM. Called once per VM in DELETE_VMID, in parallel -- no cross-VM
# ordering dependency, same reasoning as proxmox-vm-power.sh.
delete_one() {
    local vmid="$1" node="$2" name="$3"
    log info "deleting snapshot" "vmid" "${vmid}" "name" "${name}" "snapshot" "${NAME}"
    local upid
    upid=$(proxmox_curl DELETE "/nodes/${node}/qemu/${vmid}/snapshot/${NAME}") || return 1
    proxmox_wait_task "${node}" "${upid}"
}

PIDS=()
KEYS=()
for i in "${!DELETE_VMID[@]}"; do
    delete_one "${DELETE_VMID[$i]}" "${DELETE_NODE[$i]}" "${DELETE_NAME[$i]}" &
    PIDS+=($!)
    KEYS+=("${DELETE_VMID[$i]} (${DELETE_NAME[$i]})")
done

FAILED=()
for i in "${!PIDS[@]}"; do
    if ! wait "${PIDS[$i]}"; then
        FAILED+=("${KEYS[$i]}")
    fi
done

if [ "${#FAILED[@]}" -gt 0 ]; then
    log error "failed to delete snapshot on some VMs" "vms" "${FAILED[*]}"
    exit 1
fi

log info "Snapshot '${NAME}' deleted from all selected VMs." "vms" "${KEYS[*]}"
