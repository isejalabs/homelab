#!/bin/sh
set -eu

CYAN='\033[1;36m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

usage() {
    echo "Usage: $(basename "$0") -e <env> -n <ns> <app>" >&2
    exit 1
}

APP=""
ENV=""
NS=""
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

case "${ENV}" in
    dbg | dev | head | poc | prod | qa | rebuild | src) ;;
    *)
        printf "${RED}ERROR: -e/--env must be one of dbg|dev|head|poc|prod|qa|rebuild|src (got: '%s')${NC}\n" "${ENV}" >&2
        exit 1
        ;;
esac

if [ -z "${NS}" ]; then
    printf "${RED}ERROR: -n/--namespace is required${NC}\n" >&2
    exit 1
fi

if [ -z "${APP}" ]; then
    printf "${RED}ERROR: app name is required${NC}\n" >&2
    usage
fi

CTX="admin@${ENV}-homelab"

if ! kubectl --context "${CTX}" get snapshotpolicy "${APP}" -n "${NS}" >/dev/null 2>&1; then
    printf "${RED}ERROR: SnapshotPolicy '%s' not found in namespace '%s'${NC}\n" "${APP}" "${NS}" >&2
    exit 1
fi

printf "${CYAN}Triggering a manual snapshot for %s in %s (%s)...${NC}\n" "${APP}" "${NS}" "${ENV}"
NAME=$(kubectl --context "${CTX}" create -o jsonpath='{.metadata.name}' -f - <<EOF
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

printf "${CYAN}Waiting for it to complete...${NC}\n"
PHASE=""
for _ in $(seq 1 60); do
    PHASE=$(kubectl --context "${CTX}" get snapshot "${NAME}" -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [ "${PHASE}" = "Succeeded" ]; then
        break
    elif [ "${PHASE}" = "Failed" ]; then
        printf "${RED}ERROR: snapshot failed. Last log line:${NC}\n"
        kubectl --context "${CTX}" get snapshot "${NAME}" -n "${NS}" -o jsonpath='{.status.logTail}'
        echo
        exit 1
    fi
    echo "  status: ${PHASE:-Pending}"
    sleep 5
done

if [ "${PHASE}" != "Succeeded" ]; then
    printf "${RED}ERROR: timed out waiting for snapshot %s to complete (last phase: %s)${NC}\n" "${NAME}" "${PHASE:-unknown}" >&2
    exit 1
fi

STATS=$(kubectl --context "${CTX}" get snapshot "${NAME}" -n "${NS}" -o jsonpath='{.status.stats}')
printf "${GREEN}Backup completed: %s (%s)${NC}\n" "${NAME}" "${STATS}"
