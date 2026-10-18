#!/bin/bash
# Rolls an app's existing PVC back to one of its Longhorn snapshots. The Kubernetes side is automated; the
# revert itself is a manual step in the Longhorn UI, because Longhorn only exposes it through the
# longhorn-manager API after attaching the volume in maintenance mode (not as a CRD).
#
# Steps: pick the snapshot -> confirm -> take a `pre-restore-*` safety snapshot of the current data ->
# suspend the owning Flux object and scale the Deployment to 0 -> wait for the volume to detach -> pause for
# the manual revert in the Longhorn UI -> verify the volume is detached again -> resume Flux and scale back
# up (see kopiur-restore.sh for why scaling back up is done explicitly rather than left to Flux).
#
# The PVC and PV are never touched, so kopiur's dataSourceRef/Restore wiring stays intact.
# Snapshot selection: default is the newest snapshot; --snapshot <name> picks an exact one; --at <timestamp>
# picks the newest at or before an RFC3339 UTC time (e.g. 2026-10-17T14:00:00Z). Hourly snapshots only go
# back ~24h (see longhorn-snapshot-list.sh).
#
# Usage: scripts/longhorn-snapshot-restore.sh -e <env> -n <ns> [--deploy <name>] [--snapshot <name> | --at <ts>] <app>
# <app> is the PVC name; the Deployment defaults to the same name. Deployments only.
set -euo pipefail

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"
. "${SCRIPTS_DIR}/lib/longhorn.sh"

usage() {
    echo "Usage: $(basename "$0") -e <env> -n <ns> [--deploy <name>] [--snapshot <name> | --at <ts>] <app>" >&2
    exit 1
}

APP=""
ENV=""
NS=""
DEPLOY=""
SNAPSHOT=""
AT=""
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
        --deploy)
            DEPLOY="$2"
            shift 2
            ;;
        --snapshot)
            SNAPSHOT="$2"
            shift 2
            ;;
        --at)
            AT="$2"
            shift 2
            ;;
        -h | --help) usage ;;
        -*) unknown_flag "$1" ;;
        *)
            APP="$1"
            shift
            ;;
    esac
done

# Like kopiur-restore.sh: a destructive run must name its target cluster explicitly.
validate_environment "${ENV}"
CTX=$(kubecontext_for_environment "${ENV}")
CTX_ARGS=(--context "${CTX}")
LOG_CTX="${CTX}"

if [ -z "${NS}" ]; then
    log fatal "-n/--namespace is required"
    exit 1
fi
if [ -z "${APP}" ]; then
    log error "app name is required"
    usage
fi
if [ -n "${SNAPSHOT}" ] && [ -n "${AT}" ]; then
    log fatal "--snapshot and --at are mutually exclusive"
    exit 1
fi
DEPLOY="${DEPLOY:-${APP}}"

if ! kubectl "${CTX_ARGS[@]}" get deployment "${DEPLOY}" -n "${NS}" >/dev/null 2>&1; then
    log fatal "Deployment not found (pass --deploy if it differs from the app name; only Deployments are supported)" "deployment" "${DEPLOY}" "namespace" "${NS}"
    exit 1
fi

VOLUME=$(longhorn_volumes "${NS}" "${APP}" | awk '{ print $1 }')
if [ -z "${VOLUME}" ]; then
    log fatal "no Longhorn volume found for this PVC" "app" "${APP}" "namespace" "${NS}"
    exit 1
fi

PICKED=$(longhorn_pick_snapshot "${VOLUME}" "${SNAPSHOT}" "${AT}")
if [ -z "${PICKED}" ]; then
    log fatal "no matching ready snapshot found -- see 'just backup::longhorn-snapshot::list'" "volume" "${VOLUME}" "snapshot" "${SNAPSHOT:-<latest>}" "at" "${AT:-<none>}"
    exit 1
fi
read -r TARGET TARGET_TIME <<<"${PICKED}"

log info "Selected snapshot" "app" "${APP}" "namespace" "${NS}" "volume" "${VOLUME}" "snapshot" "${TARGET}" "created" "${TARGET_TIME}"
if ! gum confirm "Revert ${NS}/${APP} to snapshot ${TARGET} (${TARGET_TIME})? All data written after that time is discarded (a pre-restore safety snapshot is taken first)."; then
    log info "Aborted, nothing changed."
    exit 1
fi

ORIG_REPLICAS=$(kubectl "${CTX_ARGS[@]}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.spec.replicas}')
HR=$(kubectl "${CTX_ARGS[@]}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/name}' 2>/dev/null || true)
KS=$(kubectl "${CTX_ARGS[@]}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.kustomize\.toolkit\.fluxcd\.io/name}' 2>/dev/null || true)
if [ -z "${HR}" ] && [ -z "${KS}" ]; then
    log fatal "could not determine the owning Flux object for this deployment (no helm.toolkit.fluxcd.io/name or kustomize.toolkit.fluxcd.io/name label)" "namespace" "${NS}" "deployment" "${DEPLOY}"
    exit 1
fi

# Safety snapshot while the app is still running, so a wrong pick can itself be reverted. Done before any
# change, because a detached volume cannot be snapshotted.
log info "Taking a pre-restore safety snapshot" "step" "1/6"
SAFETY=$(kubectl "${CTX_ARGS[@]}" create -o jsonpath='{.metadata.name}' -f - <<YAML
apiVersion: longhorn.io/v1beta2
kind: Snapshot
metadata:
  generateName: pre-restore-${APP:0:30}-
  namespace: longhorn-system
  labels:
    longhornvolume: ${VOLUME}
spec:
  createSnapshot: true
  volume: ${VOLUME}
YAML
)
READY=""
for _ in $(seq 1 60); do
    READY=$(kubectl "${CTX_ARGS[@]}" -n longhorn-system get snapshots.longhorn.io "${SAFETY}" -o jsonpath='{.status.readyToUse}' 2>/dev/null || true)
    [ "${READY}" = "true" ] && break
    sleep 2
done
if [ "${READY}" != "true" ]; then
    log fatal "safety snapshot did not become ready -- nothing else was changed" "snapshot" "${SAFETY}"
    exit 1
fi
log info "Safety snapshot ready" "snapshot" "${SAFETY}"

# Suspends whichever Flux object owns the Deployment so it cannot fight the manual scale-down, and defines
# `resume` to resume that same object afterwards.
if [ -n "${HR}" ]; then
    HR_NS=$(kubectl "${CTX_ARGS[@]}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/namespace}')
    log info "Suspending HelmRelease" "step" "2/6" "helmrelease" "${HR}" "namespace" "${HR_NS}"
    flux "${CTX_ARGS[@]}" suspend helmrelease "${HR}" -n "${HR_NS}"
    resume() { flux "${CTX_ARGS[@]}" resume helmrelease "${HR}" -n "${HR_NS}"; }
else
    log info "Suspending Kustomization" "step" "2/6" "kustomization" "${KS}"
    flux "${CTX_ARGS[@]}" suspend kustomization "${KS}"
    resume() { flux "${CTX_ARGS[@]}" resume kustomization "${KS}"; }
fi

log info "Scaling down and waiting for the volume to detach" "step" "3/6" "deployment" "${DEPLOY}"
kubectl "${CTX_ARGS[@]}" scale deployment "${DEPLOY}" -n "${NS}" --replicas=0
STATE=""
for _ in $(seq 1 60); do
    STATE=$(longhorn_volume_state "${VOLUME}")
    [ "${STATE}" = "detached" ] && break
    sleep 2
done
if [ "${STATE}" != "detached" ]; then
    log fatal "volume did not detach -- Flux is still suspended and the Deployment scaled to 0; resume manually or re-run" "volume" "${VOLUME}" "state" "${STATE:-unknown}"
    exit 1
fi

# The manual step. Loops until the volume is detached again, since the UI revert requires an attach (in
# maintenance mode) and a leftover attachment would block the app from starting.
log info "Manual step: revert in the Longhorn UI" "step" "4/6" "volume" "${VOLUME}" "snapshot" "${TARGET}"
UI_HOST=$(kubectl "${CTX_ARGS[@]}" -n longhorn-system get httproute longhorn -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null || true)
cat >&2 <<MSG

  1. Open the Longhorn UI: https://${UI_HOST:-<longhorn HTTPRoute hostname>}
  2. Volume '${VOLUME}' -> Attach, tick "Maintenance mode", pick any node
  3. In the volume's snapshot list, open '${TARGET}' (${TARGET_TIME}) -> Revert
  4. Detach the volume again

  In case the Longhorn UI is not available via its HTTPRoute:
     kubectl ${CTX_ARGS[*]} -n longhorn-system port-forward svc/longhorn-frontend 8080:80   (then open http://localhost:8080)

MSG
while true; do
    gum confirm "Reverted to ${TARGET} and the volume is detached again?" || {
        log warn "Not confirmed. Flux stays suspended and the Deployment at 0; re-run or resume manually."
        exit 1
    }
    STATE=$(longhorn_volume_state "${VOLUME}")
    [ "${STATE}" = "detached" ] && break
    log warn "volume is not detached yet" "state" "${STATE}"
done

log info "Resuming Flux" "step" "5/6"
resume
log info "Scaling back up" "step" "6/6" "deployment" "${DEPLOY}" "replicas" "${ORIG_REPLICAS}"
kubectl "${CTX_ARGS[@]}" scale deployment "${DEPLOY}" -n "${NS}" --replicas="${ORIG_REPLICAS}"
kubectl "${CTX_ARGS[@]}" rollout status deployment "${DEPLOY}" -n "${NS}" --timeout=300s

log info "Done. Undo with --snapshot ${SAFETY} if the result is wrong."
