#!/bin/bash
set -euo pipefail

CYAN='\033[1;36m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

usage() {
    echo "Usage: $(basename "$0") -e <env> (-n <ns> | -A)" >&2
    exit 1
}

ENV=""
NS=""
ALL=0
while [ $# -gt 0 ]; do
    case "$1" in
        -e | --env)
            ENV="$2"
            shift 2
            ;;
        -n | --namespace)
            NS="$2"
            shift 2
            ;;
        -A | --all-namespaces)
            ALL=1
            shift
            ;;
        -h | --help) usage ;;
        *)
            printf "${RED}ERROR: unknown argument: %s${NC}\n" "$1" >&2
            usage
            ;;
    esac
done

case "${ENV}" in
    dbg | dev | head | poc | prod | qa | rebuild | src) ;;
    *)
        printf "${RED}ERROR: -e/--env must be one of dbg|dev|head|poc|prod|qa|rebuild|src (got: '%s')${NC}\n" "${ENV}" >&2
        exit 1
        ;;
esac

if [ "${ALL}" -eq 1 ] && [ -n "${NS}" ]; then
    printf "${RED}ERROR: -n/--namespace and -A/--all-namespaces are mutually exclusive${NC}\n" >&2
    exit 1
fi
if [ "${ALL}" -eq 0 ] && [ -z "${NS}" ]; then
    printf "${RED}ERROR: one of -n/--namespace or -A/--all-namespaces is required${NC}\n" >&2
    exit 1
fi

CTX="admin@${ENV}-homelab"

if [ "${ALL}" -eq 1 ]; then
    POLICIES=$(kubectl --context "${CTX}" get snapshotpolicy -A -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.namespace}{"\n"}{end}')
else
    POLICIES=$(kubectl --context "${CTX}" get snapshotpolicy -n "${NS}" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.namespace}{"\n"}{end}')
fi

if [ -z "${POLICIES}" ]; then
    printf "${RED}ERROR: no SnapshotPolicies found${NC}\n" >&2
    exit 1
fi

printf "${CYAN}Triggering backups for all apps...${NC}\n"

PIDS=()
KEYS=()
while IFS=' ' read -r APP APP_NS; do
    [ -z "${APP}" ] && continue
    echo "  -> ${APP} (${APP_NS})"
    "$(dirname "$0")/kopiur-backup.sh" -e "${ENV}" -n "${APP_NS}" "${APP}" &
    PIDS+=($!)
    KEYS+=("${APP}/${APP_NS}")
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
