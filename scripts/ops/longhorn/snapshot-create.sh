#!/bin/bash
# Triggers a manual Longhorn volume snapshot for one app, or every Longhorn-backed PVC in scope (--all), and
# waits for each Snapshot to become readyToUse. <app> is the PVC name (same as for kopiur-*.sh).
#
# A manual snapshot carries no RecurringJob label, so none of the RecurringJobs' retain counts ever prune it:
# it stays until deleted (`kubectl -n longhorn-system delete snapshots.longhorn.io <name>`).
#
# Usage: scripts/longhorn-snapshot-create.sh [-e <env>] (-n <ns> | -A) [--all] [<app>]
# <app> and --all are mutually exclusive; -n/--namespace and -A/--all-namespaces are mutually exclusive;
# -A/--all-namespaces requires --all (a single named app can't be looked up across every namespace).
# -e/--environment selects the kubecontext; omit it to use whatever context is already current.
set -euo pipefail

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"
. "${SCRIPTS_DIR}/lib/longhorn.sh"

usage() {
    echo "Usage: $(basename "$0") [-e <env>] (-n <ns> | -A) [--all] [<app>]" >&2
    exit 1
}

APP=""
ENV=""
NS=""
ALL_NS=0
ALL=0
while [ $# -gt 0 ]; do
    case "$1" in
        -e | --environment)
            ENV="$2"
            shift 2
            ;;
        -n | --namespace)
            NS="$2"
            shift 2
            ;;
        -A | --all-namespaces)
            ALL_NS=1
            shift
            ;;
        --all)
            ALL=1
            shift
            ;;
        -h | --help) usage ;;
        -*) unknown_flag "$1" ;;
        *)
            APP="$1"
            shift
            ;;
    esac
done

[ -n "${ENV}" ] && validate_environment "${ENV}"

CTX_ARGS=()
[ -n "${ENV}" ] && CTX_ARGS=(--context "$(kubecontext_for_environment "${ENV}")")

LOG_CTX="${ENV:+$(kubecontext_for_environment "${ENV}")}"
: "${LOG_CTX:=$(kubectl config current-context 2>/dev/null || echo unknown)}"

if [ "${ALL_NS}" -eq 1 ] && [ -n "${NS}" ]; then
    log fatal "-n/--namespace and -A/--all-namespaces are mutually exclusive"
    exit 1
fi
if [ "${ALL_NS}" -eq 0 ] && [ -z "${NS}" ]; then
    log fatal "one of -n/--namespace or -A/--all-namespaces is required"
    exit 1
fi
if [ "${ALL}" -eq 1 ] && [ -n "${APP}" ]; then
    log fatal "<app> and --all are mutually exclusive"
    exit 1
fi
if [ "${ALL}" -eq 0 ] && [ -z "${APP}" ]; then
    log fatal "an app name is required unless --all is given"
    exit 1
fi
if [ "${ALL}" -eq 0 ] && [ "${ALL_NS}" -eq 1 ]; then
    log fatal "-A/--all-namespaces requires --all -- a single named app cannot be looked up across every namespace"
    exit 1
fi

# Creates a Snapshot CR for one Longhorn volume and polls until it is readyToUse. Returns non-zero on
# timeout so callers (single-app path and the --all parallel loop) can track success/failure per app.
snapshot_one() {
    local volume="$1" ns="$2" app="$3"

    log info "Triggering a manual snapshot" "app" "${app}" "namespace" "${ns}" "volume" "${volume}"
    local name
    name=$(kubectl ${CTX_ARGS[@]+"${CTX_ARGS[@]}"} create -o jsonpath='{.metadata.name}' -f - <<YAML
apiVersion: longhorn.io/v1beta2
kind: Snapshot
metadata:
  generateName: manual-${app:0:30}-
  namespace: longhorn-system
  labels:
    longhornvolume: ${volume}
spec:
  createSnapshot: true
  volume: ${volume}
YAML
    )

    local ready=""
    for _ in $(seq 1 60); do
        ready=$(kubectl ${CTX_ARGS[@]+"${CTX_ARGS[@]}"} -n longhorn-system get snapshots.longhorn.io "${name}" -o jsonpath='{.status.readyToUse}' 2>/dev/null || true)
        [ "${ready}" = "true" ] && break
        sleep 2
    done

    if [ "${ready}" != "true" ]; then
        log error "timed out waiting for snapshot to become ready" "app" "${app}" "namespace" "${ns}" "snapshot" "${name}"
        return 1
    fi
    log info "snapshot ready" "app" "${app}" "namespace" "${ns}" "snapshot" "${name}"
}

if [ "${ALL}" -eq 1 ]; then
    SCOPE="${NS}"
    [ "${ALL_NS}" -eq 1 ] && SCOPE="-A"
    TARGETS=$(longhorn_volumes "${SCOPE}")
else
    TARGETS=$(longhorn_volumes "${NS}" "${APP}")
fi

if [ -z "${TARGETS}" ]; then
    log fatal "no Longhorn volume found for the given scope/app" "app" "${APP:-<all>}" "namespace" "${NS:--A}"
    exit 1
fi

PIDS=()
KEYS=()
while IFS=' ' read -r volume ns pvc; do
    [ -z "${volume}" ] && continue
    snapshot_one "${volume}" "${ns}" "${pvc}" &
    PIDS+=($!)
    KEYS+=("${pvc}/${ns}")
done <<<"${TARGETS}"

FAILED=()
for i in "${!PIDS[@]}"; do
    wait "${PIDS[$i]}" || FAILED+=("${KEYS[$i]}")
done

if [ ${#FAILED[@]} -gt 0 ]; then
    log error "failed snapshots" "apps" "${FAILED[*]}"
    exit 1
fi
log info "All snapshots completed successfully."
