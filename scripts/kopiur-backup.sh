#!/bin/bash
set -euo pipefail

CYAN='\033[1;36m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

APP="$1"
NS="${2:-$(kubectl config view --minify -o jsonpath='{..namespace}')}"

if [ -z "${NS}" ]; then
    echo -e "${RED}ERROR: no namespace given and no default namespace set in the current kubeconfig context${NC}" >&2
    exit 1
fi

if ! kubectl get snapshotpolicy "${APP}" -n "${NS}" &>/dev/null; then
    echo -e "${RED}ERROR: SnapshotPolicy '${APP}' not found in namespace '${NS}'${NC}" >&2
    exit 1
fi

echo -e "${CYAN}Triggering a manual snapshot for ${APP} in ${NS}...${NC}"
NAME=$(kubectl create -o jsonpath='{.metadata.name}' -f - <<EOF
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Snapshot
metadata:
  generateName: ${APP}-manual-
  namespace: ${NS}
spec:
  policyRef:
    name: ${APP}
  description: "manual backup via just kopiur::backup"
EOF
)
echo "  created: ${NAME}"

echo -e "${CYAN}Waiting for it to complete...${NC}"
PHASE=""
for _ in $(seq 1 60); do
    PHASE=$(kubectl get snapshot "${NAME}" -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [ "${PHASE}" = "Succeeded" ]; then
        break
    elif [ "${PHASE}" = "Failed" ]; then
        echo -e "${RED}ERROR: snapshot failed. Last log line:${NC}"
        kubectl get snapshot "${NAME}" -n "${NS}" -o jsonpath='{.status.logTail}'
        echo
        exit 1
    fi
    echo "  status: ${PHASE:-Pending}"
    sleep 5
done

if [ "${PHASE}" != "Succeeded" ]; then
    echo -e "${RED}ERROR: timed out waiting for snapshot ${NAME} to complete (last phase: ${PHASE:-unknown})${NC}" >&2
    exit 1
fi

STATS=$(kubectl get snapshot "${NAME}" -n "${NS}" -o jsonpath='{.status.stats}')
echo -e "${GREEN}Backup completed: ${NAME} (${STATS})${NC}"
