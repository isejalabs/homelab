#!/bin/sh
# Gives an app a blank PVC, bypassing its existing kopiur backups without deleting them -- for the case
# where you want to import data into an app through some other means (e.g. an application-level
# import/export from another environment) instead of restoring from the app's own kopiur history.
#
# kopiur's Restore CR resolves which snapshot (if any) populates a *new* PVC once, at that PVC's creation.
# docs/kopiur-backup-restore.md's "restore a specific older snapshot" procedure confirms live that patching
# a Restore's own spec.source forces it to re-resolve on the next PVC claim, even though the object itself
# isn't recreated. This script uses the same lever in the opposite direction: it points spec.source.fromPolicy
# at a throwaway SnapshotPolicy, created here specifically so it can never have a real Snapshot under it, so
# the next PVC claim resolves NoSnapshot and -- since every Restore this repo generates sets
# spec.policy.onMissingSnapshot: Continue -- binds an empty volume, exactly like an app's very first deploy.
# The app's actual snapshots (and its real SnapshotPolicy) are never touched.
#
# fromPolicy.name has to reference a SnapshotPolicy that actually *exists* -- kopiur derives the repository
# connection from it and won't even attempt resolution otherwise (Restore just stalls on "waiting for
# SnapshotPolicy ... to exist" forever, confirmed live rebuild/unifi-mongodb, 2026-09-18). A policy name with
# no matching object is not the same as a policy with no matching Snapshots, which is what earlier revisions
# of this script assumed. So a minimal SnapshotPolicy is created under the bogus name before the Restore is
# repointed at it: same repository as the app's real one (fiona), and a source PVC name guaranteed not to
# exist (spec.sources requires at least one entry, but nothing ever reads it back -- no SnapshotSchedule
# references this throwaway policy, so nothing ever tries to snapshot that nonexistent PVC either).
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
CTX=$(kubecontext_for_environment "${ENV}")
# Recorded for log()'s automatic "cluster" field (see lib/common.sh) so every log line below -- not just
# error paths -- shows which cluster this destructive run is acting on (#1305).
LOG_CLUSTER="${CTX}"

if [ -z "${NS}" ]; then
    log fatal "-n/--namespace is required"
    exit 1
fi

if [ -z "${APP}" ]; then
    log error "app name is required"
    usage
fi

DEPLOY="${DEPLOY:-${APP}}"
BOGUS_POLICY="${APP}-bypass-restore"

if ! kubectl --context "${CTX}" get pvc "${APP}" -n "${NS}" >/dev/null 2>&1; then
    log fatal "PVC not found -- <app> is the storage/kopiur name (same as the PVC itself), not necessarily the Deployment name; if this app's Deployment is named differently, pass --deploy too (e.g. unifi-mongodb's Deployment is named mongodb)" "app" "${APP}" "namespace" "${NS}" "deploy" "${DEPLOY}"
    exit 1
fi

if ! kubectl --context "${CTX}" get restore "${APP}" -n "${NS}" >/dev/null 2>&1; then
    log fatal "Restore object not found -- this app may not be wired up via apps/storage/pvc or pvc-no-backup" "app" "${APP}" "namespace" "${NS}"
    exit 1
fi

if ! kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" >/dev/null 2>&1; then
    log fatal "Deployment not found (pass --deploy if the deployment name differs from the app name)" "deployment" "${DEPLOY}" "namespace" "${NS}"
    exit 1
fi

# Captured up front so the app is scaled back to exactly what it was, not a hardcoded 1.
ORIG_REPLICAS=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.spec.replicas}')

# Same detection as kopiur-restore.sh: exactly one of HR/KS ends up non-empty.
HR=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/name}' 2>/dev/null || true)
KS=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.kustomize\.toolkit\.fluxcd\.io/name}' 2>/dev/null || true)

if [ -n "${HR}" ]; then
    HR_NS=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/namespace}')
    log info "Suspending HelmRelease" "step" "1/9" "helmrelease" "${HR}" "namespace" "${HR_NS}"
    flux --context "${CTX}" suspend helmrelease "${HR}" -n "${HR_NS}"
    resume() {
        flux --context "${CTX}" resume helmrelease "${HR}" -n "${HR_NS}"
    }
elif [ -n "${KS}" ]; then
    log info "Suspending Kustomization" "step" "1/9" "kustomization" "${KS}"
    flux --context "${CTX}" suspend kustomization "${KS}"
    resume() {
        flux --context "${CTX}" resume kustomization "${KS}"
    }
else
    log fatal "could not determine the owning Flux object for this deployment (no helm.toolkit.fluxcd.io/name or kustomize.toolkit.fluxcd.io/name label -- is it managed by Flux at all?)" "namespace" "${NS}" "deployment" "${DEPLOY}"
    exit 1
fi

log info "Scaling down" "step" "2/9" "deployment" "${DEPLOY}" "namespace" "${NS}"
kubectl --context "${CTX}" scale deployment "${DEPLOY}" -n "${NS}" --replicas=0
kubectl --context "${CTX}" wait pod -l app="${DEPLOY}" -n "${NS}" --for=delete --timeout=120s 2>/dev/null || true

# Same repository as the app's real SnapshotPolicy, so kopiur can still derive/verify the backend connection;
# the source PVC name is guaranteed not to exist, and nothing (no SnapshotSchedule) ever references this
# policy to try snapshotting it anyway -- it exists purely so fromPolicy.name below resolves to a real object
# with zero matching Snapshots, not to ever actually back anything up.
log info "Creating a throwaway SnapshotPolicy for the bypass" "step" "3/9" "bogus_policy" "${BOGUS_POLICY}"
kubectl --context "${CTX}" apply -f - <<EOF
apiVersion: kopiur.home-operations.com/v1alpha1
kind: SnapshotPolicy
metadata:
  name: ${BOGUS_POLICY}
  namespace: ${NS}
spec:
  repository:
    kind: ClusterRepository
    name: fiona
  sources:
    - pvc:
        name: ${BOGUS_POLICY}-nonexistent
EOF

# Points the Restore at that throwaway policy, so the next PVC claim below resolves NoSnapshot instead of the
# app's real latest backup. Existing Snapshot/backup data and the app's real SnapshotPolicy are untouched.
log info "Pointing Restore at the bypass policy" "step" "4/9" "app" "${APP}" "bogus_policy" "${BOGUS_POLICY}"
kubectl --context "${CTX}" patch restore "${APP}" -n "${NS}" --type merge \
    -p "{\"spec\":{\"source\":{\"fromPolicy\":{\"name\":\"${BOGUS_POLICY}\",\"offset\":0}}}}"

# Flux stays suspended, so the PVC has to be recreated manually rather than relying on a reconcile -- dump
# it first so the recreated PVC matches what git/Flux already declared (size, storageClass, etc.). The dump
# must have its binding-related fields stripped before being reapplied: a Bound PVC's own `get -o yaml`
# includes spec.volumeName pinned to its *current* PV, and reapplying that verbatim recreates a PVC statically
# pinned to that same (by then Released, not Available -- storage-class reclaimPolicy is Retain) PV instead of
# going through fresh dynamic provisioning, which never reaches the CSI populator/Restore at all and leaves
# the PVC stuck in phase Lost. Confirmed live (rebuild, unifi-mongodb, 2026-09-18).
TMP_PVC=$(mktemp)
trap 'rm -f "${TMP_PVC}"' EXIT
log info "Deleting and recreating the PVC against the bypass policy" "step" "5/9" "app" "${APP}" "namespace" "${NS}"
kubectl --context "${CTX}" get pvc "${APP}" -n "${NS}" -o json \
    | jq 'del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.finalizers, .metadata.annotations, .spec.volumeName, .status)' \
        >"${TMP_PVC}"
kubectl --context "${CTX}" delete pvc "${APP}" -n "${NS}" --wait=true
kubectl --context "${CTX}" apply -f "${TMP_PVC}"

# WaitForFirstConsumer storage classes only bind once something tries to mount the PVC -- scale back up
# before waiting for Bound, same reasoning as kopiur-restore.sh.
log info "Scaling back up" "step" "6/9" "deployment" "${DEPLOY}" "replicas" "${ORIG_REPLICAS}"
kubectl --context "${CTX}" scale deployment "${DEPLOY}" -n "${NS}" --replicas="${ORIG_REPLICAS}"

log info "Waiting for the blank PVC to bind" "step" "7/9"
PHASE=""
for _ in $(seq 1 60); do
    PHASE=$(kubectl --context "${CTX}" get pvc "${APP}" -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [ "${PHASE}" = "Bound" ] && break
    log debug "waiting for PVC to bind" "phase" "${PHASE:-Pending}"
    sleep 5
done

if [ "${PHASE}" != "Bound" ]; then
    log fatal "PVC did not reach Bound within the timeout -- check manually. Flux is still suspended, the Restore is still pointed at the bypass policy, and the throwaway SnapshotPolicy ${BOGUS_POLICY} still exists; fix up and resume manually" "last_phase" "${PHASE:-unknown}" "kustomization_or_helmrelease" "${KS}${HR}"
    exit 1
fi

log info "Blank volume is bound and ${DEPLOY} is back up. Go do the data import now (e.g. the app's own import/export tooling)." "step" "8/9"
printf 'Press Enter once the import is done, to restore normal restore-on-loss wiring and resume Flux: '
# shellcheck disable=SC2034 # the read value itself is unused, only the pause matters
read -r _confirm

log info "Reverting Restore to its normal policy, cleaning up the throwaway SnapshotPolicy, and resuming Flux" "step" "9/9" "app" "${APP}"
kubectl --context "${CTX}" patch restore "${APP}" -n "${NS}" --type merge \
    -p "{\"spec\":{\"source\":{\"fromPolicy\":{\"name\":\"${APP}\",\"offset\":0}}}}"
kubectl --context "${CTX}" delete snapshotpolicy "${BOGUS_POLICY}" -n "${NS}"
resume

log info "Done."
