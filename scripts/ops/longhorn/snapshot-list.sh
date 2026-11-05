#!/bin/bash
# Lists Longhorn volume snapshots (the hourly/daily RecurringJob ones plus manual ones), for one app or every
# app in scope, newest first. <app> is the PVC name (same as for kopiur-*.sh).
#
# Note the retention window: the hourly-snapshot RecurringJob keeps only 24 snapshots, i.e. roughly the last
# 24 hours at hourly granularity (k8s/infra/longhorn-system/longhorn/base/job-snapshot.yaml) -- unlike kopiur
# backups, which are day-based and go back weeks. Pick a snapshot by its CREATED timestamp, not by day.
#
# Usage: scripts/longhorn-snapshot-list.sh [-e <env>] (-n <ns> | -A) [<app>]
# -n/--namespace and -A/--all-namespaces are mutually exclusive; exactly one is required.
# -e/--environment selects the kubecontext; omit it to use whatever context is already current.
set -euo pipefail

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"
. "${SCRIPTS_DIR}/lib/longhorn.sh"

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

SCOPE="${NS}"
[ "${ALL_NS}" -eq 1 ] && SCOPE="-A"

VOLUMES=$(longhorn_volumes "${SCOPE}" "${APP}")
if [ -z "${VOLUMES}" ]; then
    log fatal "no Longhorn volume found for the given scope/app" "app" "${APP:-<any>}" "scope" "${SCOPE}"
    exit 1
fi

SNAPSHOTS=$(kubectl ${CTX_ARGS[@]+"${CTX_ARGS[@]}"} -n longhorn-system get snapshots.longhorn.io \
    -o jsonpath='{range .items[*]}{.spec.volume}{" "}{.metadata.name}{" "}{.status.creationTime}{" "}{.status.readyToUse}{" "}{.status.restoreSize}{" "}{.status.labels.RecurringJob}{"\n"}{end}')

# Joins the two listings on the volume name, then sorts per app, newest first (RFC3339 sorts lexically).
{
    printf 'NAMESPACE\tAPP\tSNAPSHOT\tCREATED\tREADY\tSIZE_BYTES\tSOURCE\n'
    awk -F' ' 'NR == FNR { ns[$1] = $2; pvc[$1] = $3; next }
        ($1 in pvc) { src = ($6 == "" ? "manual" : $6); printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", ns[$1], pvc[$1], $2, $3, $4, $5, src }' \
        <(printf '%s\n' "${VOLUMES}") <(printf '%s\n' "${SNAPSHOTS}") | sort -t$'\t' -k1,1 -k2,2 -k4,4r
} | column -t -s$'\t'
