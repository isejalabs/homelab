#!/bin/bash
set -euo pipefail

CYAN='\033[1;36m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

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
        -*)
            printf "${RED}ERROR: unknown flag: %s${NC}\n" "$1" >&2
            usage
            ;;
        *)
            APP="$1"
            shift
            ;;
    esac
done

if [ -n "${ENV}" ]; then
    case "${ENV}" in
        dbg | dev | head | poc | prod | qa | rebuild | src) ;;
        *)
            printf "${RED}ERROR: -e/--environment must be one of dbg|dev|head|poc|prod|qa|rebuild|src (got: '%s')${NC}\n" "${ENV}" >&2
            exit 1
            ;;
    esac
fi

if [ "${ALL_NS}" -eq 1 ] && [ -n "${NS}" ]; then
    printf "${RED}ERROR: -n/--namespace and -A/--all-namespaces are mutually exclusive${NC}\n" >&2
    exit 1
fi
if [ "${ALL_NS}" -eq 0 ] && [ -z "${NS}" ]; then
    printf "${RED}ERROR: one of -n/--namespace or -A/--all-namespaces is required${NC}\n" >&2
    exit 1
fi

if [ "${ALL}" -eq 1 ] && [ -n "${APP}" ]; then
    printf "${RED}ERROR: <app> and --all are mutually exclusive${NC}\n" >&2
    exit 1
fi
if [ "${ALL}" -eq 0 ] && [ -z "${APP}" ]; then
    printf "${RED}ERROR: an app name is required unless --all is given${NC}\n" >&2
    exit 1
fi
# Matches kubectl's own rule that a named resource can't be fetched with
# -A/--all-namespaces (only a list-style query can span every namespace).
if [ "${ALL}" -eq 0 ] && [ "${ALL_NS}" -eq 1 ]; then
    printf "${RED}ERROR: -A/--all-namespaces requires --all -- a single named app cannot be looked up across every namespace${NC}\n" >&2
    exit 1
fi

CTX_ARGS=()
if [ -n "${ENV}" ]; then
    CTX_ARGS=(--context "admin@${ENV}-homelab")
fi

backup_one() {
    local app="$1" ns="$2"

    if ! kubectl "${CTX_ARGS[@]}" get snapshotpolicy "${app}" -n "${ns}" >/dev/null 2>&1; then
        printf "${RED}ERROR: SnapshotPolicy '%s' not found in namespace '%s'${NC}\n" "${app}" "${ns}" >&2
        return 1
    fi

    printf "${CYAN}Triggering a manual snapshot for %s in %s...${NC}\n" "${app}" "${ns}"
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
    echo "  ${app}/${ns}: created ${name}"

    local phase=""
    for _ in $(seq 1 60); do
        phase=$(kubectl "${CTX_ARGS[@]}" get snapshot "${name}" -n "${ns}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
        if [ "${phase}" = "Succeeded" ]; then
            break
        elif [ "${phase}" = "Failed" ]; then
            printf "${RED}ERROR: %s/%s snapshot failed. Last log line:${NC}\n" "${app}" "${ns}"
            kubectl "${CTX_ARGS[@]}" get snapshot "${name}" -n "${ns}" -o jsonpath='{.status.logTail}'
            echo
            return 1
        fi
        sleep 5
    done

    if [ "${phase}" != "Succeeded" ]; then
        printf "${RED}ERROR: timed out waiting for %s/%s snapshot %s to complete (last phase: %s)${NC}\n" "${app}" "${ns}" "${name}" "${phase:-unknown}" >&2
        return 1
    fi

    local stats
    stats=$(kubectl "${CTX_ARGS[@]}" get snapshot "${name}" -n "${ns}" -o jsonpath='{.status.stats}')
    printf "${GREEN}%s/%s backup completed: %s (%s)${NC}\n" "${app}" "${ns}" "${name}" "${stats}"
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
    printf "${RED}ERROR: no SnapshotPolicies found${NC}\n" >&2
    exit 1
fi

printf "${CYAN}Triggering backups for all apps...${NC}\n"

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
    printf "${RED}Failed backups:${NC}\n"
    printf '  %s\n' "${FAILED[@]}"
    exit 1
fi

printf "${GREEN}All backups completed successfully.${NC}\n"
