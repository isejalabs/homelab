#!/bin/bash
# Triggers a manual kopiur Snapshot for one app, or every app with an active SnapshotPolicy in scope
# (--all), and waits for each triggered Snapshot to reach a terminal phase before reporting success/failure.
#
# Usage: scripts/kopiur-create.sh [-e <env>] (-n <ns> | -A) [--all] [<app>]
# <app> and --all are mutually exclusive; -n/--namespace and -A/--all-namespaces are mutually exclusive;
# -A/--all-namespaces requires --all (a single named app can't be looked up across every namespace).
# -e/--environment selects the kubecontext; omit it to use whatever context is already current.
set -euo pipefail

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

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

if [ "${ALL_NS}" -eq 1 ] && [ -n "${NS}" ]; then
    just log fatal "-n/--namespace and -A/--all-namespaces are mutually exclusive"
    exit 1
fi
if [ "${ALL_NS}" -eq 0 ] && [ -z "${NS}" ]; then
    just log fatal "one of -n/--namespace or -A/--all-namespaces is required"
    exit 1
fi

if [ "${ALL}" -eq 1 ] && [ -n "${APP}" ]; then
    just log fatal "<app> and --all are mutually exclusive"
    exit 1
fi
if [ "${ALL}" -eq 0 ] && [ -z "${APP}" ]; then
    just log fatal "an app name is required unless --all is given"
    exit 1
fi
# Matches kubectl's own rule that a named resource can't be fetched with
# -A/--all-namespaces (only a list-style query can span every namespace).
if [ "${ALL}" -eq 0 ] && [ "${ALL_NS}" -eq 1 ]; then
    just log fatal "-A/--all-namespaces requires --all -- a single named app cannot be looked up across every namespace"
    exit 1
fi

CTX_ARGS=()
if [ -n "${ENV}" ]; then
    CTX_ARGS=(--context "$(kubecontext_for_environment "${ENV}")")
fi

# Creates a Snapshot CR for a single app/namespace, polls its .status.phase until it's terminal, and prints
# the resulting stats (or the failing Snapshot's log tail). Returns non-zero on any failure so callers -
# both the single-app path and the --all parallel loop below - can track success/failure per app.
backup_one() {
    local app="$1" ns="$2"

    if ! kubectl "${CTX_ARGS[@]}" get snapshotpolicy "${app}" -n "${ns}" >/dev/null 2>&1; then
        just log error "SnapshotPolicy not found" "app" "${app}" "namespace" "${ns}"
        return 1
    fi

    just log info "Triggering a manual snapshot" "app" "${app}" "namespace" "${ns}"
    local name
    name=$(kubectl "${CTX_ARGS[@]}" create -o jsonpath='{.metadata.name}' -f - <<EOF
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Snapshot
metadata:
  generateName: ${app}-manual-
  namespace: ${ns}
spec:
  policyRef:
    name: ${app}
  description: "manual backup via just backup::kopiur::create"
EOF
    )
    just log info "created Snapshot" "app" "${app}" "namespace" "${ns}" "snapshot" "${name}"

    local phase=""
    for _ in $(seq 1 60); do
        phase=$(kubectl "${CTX_ARGS[@]}" get snapshot "${name}" -n "${ns}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
        if [ "${phase}" = "Succeeded" ]; then
            break
        elif [ "${phase}" = "Failed" ]; then
            just log error "snapshot failed" "app" "${app}" "namespace" "${ns}" "snapshot" "${name}"
            kubectl "${CTX_ARGS[@]}" get snapshot "${name}" -n "${ns}" -o jsonpath='{.status.logTail}'
            echo
            return 1
        fi
        sleep 5
    done

    if [ "${phase}" != "Succeeded" ]; then
        just log error "timed out waiting for snapshot to complete" "app" "${app}" "namespace" "${ns}" "snapshot" "${name}" "last_phase" "${phase:-unknown}"
        return 1
    fi

    local stats
    stats=$(kubectl "${CTX_ARGS[@]}" get snapshot "${name}" -n "${ns}" -o jsonpath='{.status.stats}')
    just log info "backup completed" "app" "${app}" "namespace" "${ns}" "snapshot" "${name}" "stats" "${stats}"
}

if [ "${ALL}" -eq 0 ]; then
    backup_one "${APP}" "${NS}"
    exit 0
fi

# --all: resolve every SnapshotPolicy in scope and back each up in parallel.
if [ "${ALL_NS}" -eq 1 ]; then
    POLICIES=$(kubectl "${CTX_ARGS[@]}" get snapshotpolicy -A -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.namespace}{"\n"}{end}')
else
    POLICIES=$(kubectl "${CTX_ARGS[@]}" get snapshotpolicy -n "${NS}" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.namespace}{"\n"}{end}')
fi

if [ -z "${POLICIES}" ]; then
    just log fatal "no SnapshotPolicies found"
    exit 1
fi

just log info "Triggering backups for all apps..."

PIDS=()
KEYS=()
while IFS=' ' read -r app ns; do
    [ -z "${app}" ] && continue
    backup_one "${app}" "${ns}" &
    PIDS+=($!)
    KEYS+=("${app}/${ns}")
done <<<"${POLICIES}"

FAILED=()
for i in "${!PIDS[@]}"; do
    if ! wait "${PIDS[$i]}"; then
        FAILED+=("${KEYS[$i]}")
    fi
done

if [ ${#FAILED[@]} -gt 0 ]; then
    just log error "failed backups" "apps" "${FAILED[*]}"
    exit 1
fi

just log info "All backups completed successfully."
