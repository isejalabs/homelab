#!/bin/bash
# Rolls back every VM belonging to <env> to a named snapshot (default "initial") and, unless --no-start,
# boots it back up -- the "Rollback" half of #1296's one-go workflow, via the Proxmox REST API -- no SSH.
# See docs/proxmox-vm-snapshots.md.
#
# Destructive: discards every disk change made since the snapshot. Requires typed confirmation unless
# -y/--yes. Proxmox only allows rolling back to a VM's MOST RECENT snapshot -- if any discovered VM has a
# newer snapshot on top of <name>, this aborts before touching any VM (see docs/proxmox-vm-snapshots.md for
# why, and how to proceed).
#
# Usage: scripts/proxmox-vm-rollback.sh -e <env> [--name <name>] [-y|--yes] [--no-start]
set -euo pipefail

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"
. "${SCRIPTS_DIR}/lib/proxmox.sh"

usage() {
    echo "Usage: $(basename "$0") -e <env> [--name <name>] [-y|--yes] [--no-start]" >&2
    exit 1
}

ENV=""
NAME="initial"
YES=0
START=1
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
        -y | --yes)
            YES=1
            shift
            ;;
        --no-start)
            START=0
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

# Pre-flight, all-or-nothing: every VM must have <name> as its MOST RECENT snapshot. Proxmox's own
# rollback semantics (PVE::AbstractConfig::snapshot_rollback, independent of storage backend) refuse
# rolling back to an older snapshot while a newer one sits on top of it -- a `force` API param exists to
# override this by destroying the newer snapshots, but this script deliberately doesn't expose it (that's
# a second, larger destructive action on top of the one asked for here; see docs/proxmox-vm-snapshots.md).
# A single VM failing this check aborts the whole rollback before any VM is touched.
MISSING=()
NOT_LATEST=()
while IFS=$'\t' read -r vmid node name _status; do
    [ -z "${vmid}" ] && continue
    snapshots=$(proxmox_curl GET "/nodes/${node}/qemu/${vmid}/snapshot") || exit 1
    if ! jq -e --arg n "${NAME}" 'any(.[]; .name == $n)' <<<"${snapshots}" >/dev/null; then
        MISSING+=("${vmid} (${name})")
        continue
    fi
    latest=$(jq -r '[.[] | select(.name != "current")] | sort_by(.snaptime) | last | .name // empty' <<<"${snapshots}")
    if [ "${latest}" != "${NAME}" ]; then
        NOT_LATEST+=("${vmid} (${name}): newest snapshot is '${latest}', not '${NAME}'")
    fi
done <<<"${VMS}"

if [ "${#MISSING[@]}" -gt 0 ]; then
    log fatal "snapshot '${NAME}' does not exist on some VMs" "vms" "${MISSING[*]}"
    exit 1
fi
if [ "${#NOT_LATEST[@]}" -gt 0 ]; then
    log fatal "'${NAME}' is not the most recent snapshot on some VMs -- Proxmox only allows rolling back to the latest snapshot; remove the newer ones first (see docs/proxmox-vm-snapshots.md)" "vms" "${NOT_LATEST[*]}"
    exit 1
fi

log info "About to roll back the following ${ENV} VMs to snapshot '${NAME}' -- this discards every disk change since then:" "env" "${ENV}"
{
    # VMS is vmid/node/name/status (proxmox_discover_vms' own field order) -- reordered here to
    # vmid/name/node/status to match `list`'s column order, not printed as-is under a mismatched header.
    printf 'VMID\tNAME\tNODE\tSTATUS\n'
    printf '%s\n' "${VMS}" | awk -F'\t' -v OFS='\t' '{print $1, $3, $2, $4}'
} | column -t -s $'\t'

if [ "${YES}" -eq 0 ]; then
    printf 'Type the environment name (%s) to confirm rollback: ' "${ENV}"
    read -r CONFIRM
    if [ "${CONFIRM}" != "${ENV}" ]; then
        log fatal "confirmation did not match -- aborting"
        exit 1
    fi
fi

rollback_one() {
    local vmid="$1" node="$2" name="$3" status="$4"
    local upid

    if [ "${status}" = "running" ]; then
        # Hard stop, not a graceful shutdown -- pointless to wait for a clean shutdown when the disk is
        # about to be reverted to a point before it anyway.
        log info "stopping VM" "vmid" "${vmid}" "name" "${name}"
        upid=$(proxmox_curl POST "/nodes/${node}/qemu/${vmid}/status/stop") || return 1
        proxmox_wait_task "${node}" "${upid}" || return 1
    fi

    log info "rolling back" "vmid" "${vmid}" "name" "${name}" "snapshot" "${NAME}"
    upid=$(proxmox_curl POST "/nodes/${node}/qemu/${vmid}/snapshot/${NAME}/rollback") || return 1
    proxmox_wait_task "${node}" "${upid}" || return 1

    if [ "${START}" -eq 1 ]; then
        log info "starting VM" "vmid" "${vmid}" "name" "${name}"
        upid=$(proxmox_curl POST "/nodes/${node}/qemu/${vmid}/status/start") || return 1
        proxmox_wait_task "${node}" "${upid}" || return 1
    fi
}

# Sequential, one VM at a time, in this version -- see #1296's follow-up for a host-grouped parallel
# design (kick off every node's VMs first, then wait). Stops attempting further VMs after the first
# failure rather than plowing ahead, so the failure report cleanly separates "already rolled back",
# "failed", and "not yet attempted" instead of leaving that ambiguous.
DONE=()
REMAINING=()
FAILED_VM=""
while IFS=$'\t' read -r vmid node name status; do
    [ -z "${vmid}" ] && continue
    if [ -n "${FAILED_VM}" ]; then
        REMAINING+=("${vmid} (${name})")
        continue
    fi
    if rollback_one "${vmid}" "${node}" "${name}" "${status}"; then
        DONE+=("${vmid} (${name})")
    else
        FAILED_VM="${vmid} (${name})"
    fi
done <<<"${VMS}"

if [ -n "${FAILED_VM}" ]; then
    log error "rollback failed -- stopped before attempting remaining VMs" \
        "failed" "${FAILED_VM}" "already_rolled_back" "${DONE[*]:-none}" "not_attempted" "${REMAINING[*]:-none}"
    exit 1
fi

log info "All ${ENV} VMs rolled back to '${NAME}' successfully." "vms" "${DONE[*]}"
