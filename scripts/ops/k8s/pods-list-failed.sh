#!/bin/sh
# Lists the pods that are not healthy - not Running, or Running with a container that is not ready
# (CrashLoopBackOff, Error, ContainerStatusUnknown, Pending, ImagePullBackOff, OOMKilled, ...) - without
# the pods of completed jobs. kubectl's field selectors cannot express this: a crash-looping pod has phase
# Running, so the state only shows in the container statuses. Columns: NAMESPACE NAME READY STATUS RESTARTS
# AGE REASON, where STATUS is the pod phase and REASON the container's waiting/terminated reason.
#
# Usage: scripts/ops/k8s/pods-list-failed.sh [-e <env>] [-n <ns>]
# -e/--environment selects the kubecontext; omit it to use whatever context is already current.
# -n/--namespace limits the list to one namespace; omit it to list all namespaces.
set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

usage() {
    echo "Usage: $(basename "$0") [-e <env>] [-n <ns>]" >&2
    exit 1
}

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
        *) unknown_flag "$1" ;;
    esac
done

[ -n "${ENV}" ] && validate_environment "${ENV}"

# CTX_ARGS is either empty or exactly "--context admin@<env>-homelab" (env is validated above) -
# deliberately word-split below to contribute zero args to kubectl when no environment was given.
CTX_ARGS=""
[ -n "${ENV}" ] && CTX_ARGS="--context $(kubecontext_for_environment "${ENV}")"

NS_ARGS="-A"
[ -n "${NS}" ] && NS_ARGS="-n ${NS}"

# Pod age in kubectl's two-unit style (7d7h, 13h15m, 6m30s), computed from the creation timestamp.
JQ_FILTER='
  def age:
    (now - (.metadata.creationTimestamp | fromdate) | floor) as $s
    | if $s >= 86400 then "\($s / 86400 | floor)d\($s % 86400 / 3600 | floor)h"
      elif $s >= 3600 then "\($s / 3600 | floor)h\($s % 3600 / 60 | floor)m"
      elif $s >= 60 then "\($s / 60 | floor)m\($s % 60)s"
      else "\($s)s" end;
  ["NAMESPACE", "NAME", "READY", "STATUS", "RESTARTS", "AGE", "REASON"],
  (.items[]
    | select(.status.phase != "Succeeded")
    | (.status.containerStatuses // []) as $cs
    | select(.status.phase != "Running" or any($cs[]; .ready | not))
    | [ .metadata.namespace,
        .metadata.name,
        "\([$cs[] | select(.ready)] | length)/\(.spec.containers | length)",
        .status.phase,
        ([$cs[].restartCount] | add // 0),
        age,
        ([$cs[] | .state.waiting.reason // .state.terminated.reason // empty] | join(",")) ])
  | @tsv'

# Captured first so a failing kubectl (unknown context, no access) stops the script - a plain pipeline would
# hide its exit status in POSIX sh.
# shellcheck disable=SC2086
PODS_JSON=$(kubectl ${CTX_ARGS} get pods ${NS_ARGS} -o json)
printf '%s' "${PODS_JSON}" | jq -r "${JQ_FILTER}" | column -t -s "$(printf '\t')"
