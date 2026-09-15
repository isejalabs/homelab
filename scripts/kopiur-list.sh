#!/bin/sh
set -eu

RED='\033[1;31m'
NC='\033[0m'

usage() {
    echo "Usage: $(basename "$0") [-e <env>] -n <ns> <app>" >&2
    exit 1
}

APP=""
ENV=""
NS=""
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

if [ -z "${NS}" ]; then
    printf "${RED}ERROR: -n/--namespace is required${NC}\n" >&2
    exit 1
fi

if [ -z "${APP}" ]; then
    printf "${RED}ERROR: app name is required${NC}\n" >&2
    usage
fi

# CTX_ARGS is either empty or exactly "--context admin@<env>-homelab" (env is
# validated above against a fixed enum) -- deliberately word-split below to
# contribute zero args to kubectl when environment wasn't given, falling back
# to whatever the current kubecontext already is.
CTX_ARGS=""
if [ -n "${ENV}" ]; then
    CTX_ARGS="--context admin@${ENV}-homelab"
fi

# shellcheck disable=SC2086
kubectl ${CTX_ARGS} get snapshot -n "${NS}" -l kopiur.home-operations.com/config="${APP}" \
    -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,ORIGIN:.status.origin,KOPIA_ID:.status.snapshot.kopiaSnapshotID,SIZE:.status.stats.sizeBytes,CREATED:.metadata.creationTimestamp
