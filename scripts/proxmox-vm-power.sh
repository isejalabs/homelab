#!/bin/bash
# Performs one power action (start/stop/shutdown/reset) on either every VM belonging to <env> or, with
# --vmid, just that one VM, via the Proxmox REST API -- no SSH. See docs/proxmox-vm-power.md.
#
# stop/shutdown/reset are destructive-ish (an ungraceful power-off, or a guest-initiated one, or a hard
# reset) and require typed confirmation (or -y/--yes) when acting environment-wide -- a single --vmid
# target already has its blast radius spelled out in the command, so it skips the prompt. start never
# prompts (starting a VM is always safe).
#
# Usage: scripts/proxmox-vm-power.sh --action <start|stop|shutdown|reset> -e <env> [--vmid <vmid>] [-y|--yes]
set -euo pipefail

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"
. "${SCRIPTS_DIR}/lib/proxmox.sh"

usage() {
    echo "Usage: $(basename "$0") --action <start|stop|shutdown|reset> -e <env> [--vmid <vmid>] [-y|--yes]" >&2
    exit 1
}

ACTION=""
ENV=""
VMID=""
YES=0
while [ $# -gt 0 ]; do
    case "$1" in
        --action)
            ACTION="$2"
            shift 2
            ;;
        -e | --environment)
            ENV="$2"
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

case "${ACTION}" in
    start | stop | shutdown | reset) ;;
    *)
        log fatal "--action must be one of: start stop shutdown reset" "got" "${ACTION}"
        exit 1
        ;;
esac
[ -z "${ENV}" ] && usage
validate_environment "${ENV}"
proxmox_load_secrets

VMS=$(proxmox_discover_vms "${ENV}")
if [ -z "${VMS}" ]; then
    log fatal "no VMs found for environment" "env" "${ENV}"
    exit 1
fi
VMS=$(printf '%s\n' "${VMS}" | proxmox_filter_vmid "${VMID}")

# Only stop/shutdown/reset are gated, and only when acting on the whole environment (no --vmid) -- see the
# file header for why. Same typed-confirmation UX as proxmox-snapshot-rollback.sh.
case "${ACTION}" in
    stop | shutdown | reset)
        if [ -z "${VMID}" ] && [ "${YES}" -eq 0 ]; then
            log info "About to ${ACTION} the following ${ENV} VMs:" "env" "${ENV}"
            {
                printf 'VMID\tNAME\tNODE\tSTATUS\n'
                printf '%s\n' "${VMS}" | awk -F'\t' -v OFS='\t' '{print $1, $3, $2, $4}'
            } | column -t -s $'\t'

            printf 'Type the environment name (%s) to confirm %s: ' "${ENV}" "${ACTION}"
            read -r CONFIRM
            if [ "${CONFIRM}" != "${ENV}" ]; then
                log fatal "confirmation did not match -- aborting"
                exit 1
            fi
        fi
        ;;
esac

# Verb for log messages only -- the actual API path segment is always $ACTION itself.
verb() {
    case "$1" in
        start) echo "starting" ;;
        stop) echo "stopping" ;;
        shutdown) echo "shutting down" ;;
        reset) echo "resetting" ;;
    esac
}

# No cross-VM ordering dependency for a power action (unlike rollback's per-VM stop-then-rollback-then-start
# sequence), so every selected VM runs concurrently -- same PID-array pattern as
# scripts/proxmox-snapshot-create.sh.
power_one() {
    local vmid="$1" node="$2" name="$3"
    log info "$(verb "${ACTION}") VM" "vmid" "${vmid}" "name" "${name}"
    proxmox_vm_power_action "${ACTION}" "${vmid}" "${node}"
}

PIDS=()
KEYS=()
while IFS=$'\t' read -r vmid node name _status; do
    [ -z "${vmid}" ] && continue
    power_one "${vmid}" "${node}" "${name}" &
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
    log error "failed to ${ACTION} some VMs" "vms" "${FAILED[*]}"
    exit 1
fi

log info "${ACTION} completed on all selected ${ENV} VMs." "vms" "${KEYS[*]}"
