#!/bin/bash
set -euo pipefail

CYAN='\033[1;36m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

NS="${1:-}"

if [ -n "${NS}" ]; then
    POLICIES=$(kubectl get snapshotpolicy -n "${NS}" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.namespace}{"\n"}{end}')
else
    POLICIES=$(kubectl get snapshotpolicy -A -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.namespace}{"\n"}{end}')
fi

if [ -z "${POLICIES}" ]; then
    echo -e "${RED}ERROR: no SnapshotPolicies found${NC}" >&2
    exit 1
fi

echo -e "${CYAN}Triggering backups for all apps...${NC}"

PIDS=()
KEYS=()
while IFS=' ' read -r APP APP_NS; do
    [ -z "${APP}" ] && continue
    echo "  -> ${APP} (${APP_NS})"
    bash "$(dirname "$0")/kopiur-backup.sh" "${APP}" "${APP_NS}" &
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
    echo -e "${RED}Failed backups:${NC}"
    printf '  %s\n' "${FAILED[@]}"
    exit 1
fi

echo -e "${GREEN}All backups completed successfully.${NC}"
