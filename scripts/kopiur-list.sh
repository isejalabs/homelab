#!/bin/sh
# Lists kopiur Snapshot CRs, for one app or every app in scope, as a custom-columns kubectl table -
# a thin wrapper around `kubectl get snapshot` that only adds the columns/filters that are actually useful.
#
# Usage: scripts/kopiur-list.sh [-e <env>] (-n <ns> | -A) [<app>]
# -n/--namespace and -A/--all-namespaces are mutually exclusive; exactly one is required.
# -e/--environment selects the kubecontext; omit it to use whatever context is already current.
# <app> filters to that app's Snapshots via the kopiur.home-operations.com/config label; omit it to list all.
set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

usage() {
    echo "Usage: $(basename "$0") [-e <env>] (-n <ns> | -A) [<app>]" >&2
    exit 1
}

APP=""
ENV=""
NS=""
ALL_NS=0
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

# CTX_ARGS is either empty or exactly "--context admin@<env>-homelab" (env is
# validated above) -- deliberately word-split below to contribute zero args to
# kubectl when environment wasn't given, falling back to whatever the current
# kubecontext already is.
CTX_ARGS=""
[ -n "${ENV}" ] && CTX_ARGS="--context $(kubecontext_for_environment "${ENV}")"

NS_ARGS="-n ${NS}"
[ "${ALL_NS}" -eq 1 ] && NS_ARGS="-A"

SELECTOR_ARGS=""
[ -n "${APP}" ] && SELECTOR_ARGS="-l kopiur.home-operations.com/config=${APP}"

# NAMESPACE/APP columns are only meaningful (and only added) when that axis
# isn't already fixed by a flag -- e.g. a single app in a single namespace
# doesn't need either repeated on every row.
CUSTOM_COLUMNS="NAME:.metadata.name"
[ "${ALL_NS}" -eq 1 ] && CUSTOM_COLUMNS="${CUSTOM_COLUMNS},NAMESPACE:.metadata.namespace"
[ -z "${APP}" ] && CUSTOM_COLUMNS="${CUSTOM_COLUMNS},APP:.metadata.labels.kopiur\.home-operations\.com/config"
CUSTOM_COLUMNS="${CUSTOM_COLUMNS},PHASE:.status.phase,ORIGIN:.status.origin,KOPIA_ID:.status.snapshot.kopiaSnapshotID,SIZE:.status.stats.sizeBytes,CREATED:.metadata.creationTimestamp"

# shellcheck disable=SC2086
kubectl ${CTX_ARGS} get snapshot ${NS_ARGS} ${SELECTOR_ARGS} -o custom-columns="${CUSTOM_COLUMNS}"
