#!/bin/sh
set -eu

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

kubectl --context "admin@${ENV}-homelab" get snapshot -n "${NS}" -l kopiur.home-operations.com/config="${APP}" \
    -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,ORIGIN:.status.origin,KOPIA_ID:.status.snapshot.kopiaSnapshotID,SIZE:.status.stats.sizeBytes,CREATED:.metadata.creationTimestamp
