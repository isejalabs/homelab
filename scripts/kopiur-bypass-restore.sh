#!/bin/sh
# Gives an app a blank PVC, bypassing its existing kopiur backups without deleting them -- for the case
# where you want to import data into an app through some other means (e.g. an application-level
# import/export from another environment) instead of restoring from the app's own kopiur history.
#
# kopiur's Restore CR resolves which snapshot (if any) populates a *new* PVC once, at that PVC's creation.
# docs/kopiur-backup-restore.md's "restore a specific older snapshot" procedure confirms live that patching
# a Restore's own spec.source forces it to re-resolve on the next PVC claim, even though the object itself
# isn't recreated. This script uses the same lever in the opposite direction: it points spec.source.fromPolicy
# at a policy name that can never match a real Snapshot (nothing is named "<app>-bypass-restore"), so the
# next PVC claim resolves NoSnapshot and -- since every Restore this repo generates sets
# spec.policy.onMissingSnapshot: Continue -- binds an empty volume, exactly like an app's very first deploy.
# The app's actual snapshots are never touched.
#
# Flux must stay suspended for the whole bypass window, not just during the delete/recreate step: resuming
# it early would reconcile the Restore object back to its git-declared (real) policy name before the empty
# PVC has actually claimed and resolved against the bogus one. So, unlike kopiur-restore.sh, this script
# does not resume Flux until the bogus patch has already been reverted -- the PVC is deleted and manually
# recreated (dumped via `kubectl get -o yaml` beforehand) while Flux is still suspended, following the same
# pattern as the doc's specific-snapshot procedure.
#
# This is interactive: after the blank PVC binds and the app is scaled back up, the script pauses for you to
# do the actual data import, then reverts the bogus policy name and resumes Flux once you confirm. Reverting
# is not optional busywork -- leaving the Restore pinned to a policy that never matches anything would mean a
# *future*, accidental PVC loss for this app restores empty instead of from its real latest backup.
set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

usage() {
    echo "Usage: $(basename "$0") -e <env> -n <ns> [--deploy <name>] <app>" >&2
    exit 1
}

APP=""
ENV=""
NS=""
DEPLOY=""
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
        -h | --help) usage ;;
        -*) unknown_flag "$1" ;;
        *)
            APP="$1"
            shift
            ;;
    esac
done

# This is destructive/disruptive enough (scales the app down, temporarily blanks its volume) that the
# target cluster should always be named explicitly, same as kopiur-restore.sh.
validate_environment "${ENV}"

if [ -z "${NS}" ]; then
    just log fatal "-n/--namespace is required"
    exit 1
fi

if [ -z "${APP}" ]; then
    just log error "app name is required"
    usage
fi

DEPLOY="${DEPLOY:-${APP}}"
CTX=$(kubecontext_for_environment "${ENV}")
BOGUS_POLICY="${APP}-bypass-restore"

if ! kubectl --context "${CTX}" get pvc "${APP}" -n "${NS}" >/dev/null 2>&1; then
    just log fatal "PVC not found" "app" "${APP}" "namespace" "${NS}"
    exit 1
fi

if ! kubectl --context "${CTX}" get restore "${APP}" -n "${NS}" >/dev/null 2>&1; then
    just log fatal "Restore object not found -- this app may not be wired up via apps/storage/pvc or pvc-no-backup" "app" "${APP}" "namespace" "${NS}"
    exit 1
fi

if ! kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" >/dev/null 2>&1; then
    just log fatal "Deployment not found (pass --deploy if the deployment name differs from the app name)" "deployment" "${DEPLOY}" "namespace" "${NS}"
    exit 1
fi

# Captured up front so the app is scaled back to exactly what it was, not a hardcoded 1.
ORIG_REPLICAS=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.spec.replicas}')

# Same detection as kopiur-restore.sh: exactly one of HR/KS ends up non-empty.
HR=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/name}' 2>/dev/null || true)
KS=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.kustomize\.toolkit\.fluxcd\.io/name}' 2>/dev/null || true)

if [ -n "${HR}" ]; then
    HR_NS=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/namespace}')
    just log info "Suspending HelmRelease" "step" "1/8" "helmrelease" "${HR}" "namespace" "${HR_NS}"
    flux --context "${CTX}" suspend helmrelease "${HR}" -n "${HR_NS}"
    resume() {
        flux --context "${CTX}" resume helmrelease "${HR}" -n "${HR_NS}"
    }
elif [ -n "${KS}" ]; then
    just log info "Suspending Kustomization" "step" "1/8" "kustomization" "${KS}"
    flux --context "${CTX}" suspend kustomization "${KS}"
    resume() {
        flux --context "${CTX}" resume kustomization "${KS}"
    }
else
    just log fatal "could not determine the owning Flux object for this deployment (no helm.toolkit.fluxcd.io/name or kustomize.toolkit.fluxcd.io/name label -- is it managed by Flux at all?)" "namespace" "${NS}" "deployment" "${DEPLOY}"
    exit 1
fi

just log info "Scaling down" "step" "2/8" "deployment" "${DEPLOY}" "namespace" "${NS}"
kubectl --context "${CTX}" scale deployment "${DEPLOY}" -n "${NS}" --replicas=0
kubectl --context "${CTX}" wait pod -l app="${DEPLOY}" -n "${NS}" --for=delete --timeout=120s 2>/dev/null || true

# Points the Restore at a policy name that can never match a real Snapshot, so the next PVC claim below
# resolves NoSnapshot instead of the app's real latest backup. Existing Snapshot/backup data is untouched.
just log info "Pointing Restore at a bypass policy (no snapshots exist under this name)" "step" "3/8" "app" "${APP}" "bogus_policy" "${BOGUS_POLICY}"
kubectl --context "${CTX}" patch restore "${APP}" -n "${NS}" --type merge \
    -p "{\"spec\":{\"source\":{\"fromPolicy\":{\"name\":\"${BOGUS_POLICY}\",\"offset\":0}}}}"

# Flux stays suspended, so the PVC has to be recreated manually rather than relying on a reconcile -- dump
# it first so the recreated PVC matches what git/Flux already declared (size, storageClass, etc.).
TMP_PVC=$(mktemp)
trap 'rm -f "${TMP_PVC}"' EXIT
just log info "Deleting and recreating the PVC against the bypass policy" "step" "4/8" "app" "${APP}" "namespace" "${NS}"
kubectl --context "${CTX}" get pvc "${APP}" -n "${NS}" -o yaml >"${TMP_PVC}"
kubectl --context "${CTX}" delete pvc "${APP}" -n "${NS}" --wait=true
kubectl --context "${CTX}" apply -f "${TMP_PVC}"

# WaitForFirstConsumer storage classes only bind once something tries to mount the PVC -- scale back up
# before waiting for Bound, same reasoning as kopiur-restore.sh.
just log info "Scaling back up" "step" "5/8" "deployment" "${DEPLOY}" "replicas" "${ORIG_REPLICAS}"
kubectl --context "${CTX}" scale deployment "${DEPLOY}" -n "${NS}" --replicas="${ORIG_REPLICAS}"

just log info "Waiting for the blank PVC to bind" "step" "6/8"
PHASE=""
for _ in $(seq 1 60); do
    PHASE=$(kubectl --context "${CTX}" get pvc "${APP}" -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [ "${PHASE}" = "Bound" ] && break
    just log debug "waiting for PVC to bind" "phase" "${PHASE:-Pending}"
    sleep 5
done

if [ "${PHASE}" != "Bound" ]; then
    just log fatal "PVC did not reach Bound within the timeout -- check manually. Flux is still suspended and the Restore is still pointed at the bypass policy; fix up and resume manually" "last_phase" "${PHASE:-unknown}" "kustomization_or_helmrelease" "${KS}${HR}"
    exit 1
fi

just log info "Blank volume is bound and ${DEPLOY} is back up. Go do the data import now (e.g. the app's own import/export tooling)." "step" "7/8"
printf 'Press Enter once the import is done, to restore normal restore-on-loss wiring and resume Flux: '
# shellcheck disable=SC2034 # the read value itself is unused, only the pause matters
read -r _confirm

just log info "Reverting Restore to its normal policy and resuming Flux" "step" "8/8" "app" "${APP}"
kubectl --context "${CTX}" patch restore "${APP}" -n "${NS}" --type merge \
    -p "{\"spec\":{\"source\":{\"fromPolicy\":{\"name\":\"${APP}\",\"offset\":0}}}}"
resume

just log info "Done."
