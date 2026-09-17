#!/bin/sh
# Restores an app's PVC from its latest kopiur snapshot.
#
# kopiur's Restore CR populates a PVC only once, at creation (it's a CSI
# populator, not a continuous sync target like VolSync's ReplicationDestination),
# and pins its snapshot resolution the first time it resolves and never
# re-evaluates it -- so both the PVC *and* the Restore object must be deleted,
# or a stale pin (e.g. an app's very first, snapshot-less deploy pinning
# NoSnapshot) gets silently reused instead of resolving against whatever
# snapshots actually exist now. See docs/kopiur-backup-restore.md.
#
# Flux actively reverts manual changes (a scaled-down Deployment gets scaled
# back up on the next reconcile) for a plain-manifest app, whose Kustomization
# does real drift detection -- but NOT for a Helm-based app: `helm upgrade`
# computes its patch as a diff against the *previous release's* declared
# values, not against live state, so a field that hasn't changed between
# revisions (e.g. replicas, unchanged since the app was first installed) is
# simply absent from the patch and an out-of-band `kubectl scale` to it is
# never corrected by a later reconcile alone. Confirmed live (dev, rebuild):
# `flux resume helmrelease` reliably completes, but the Deployment stays at
# 0 replicas indefinitely. So this script scales back up explicitly itself
# rather than assuming Flux/Helm will do it.
#
# Which kind of object owns a Deployment is detected from Flux's own
# provenance labels: a plain-manifest app carries
# kustomize.toolkit.fluxcd.io/name directly; a Helm-based app carries
# helm.toolkit.fluxcd.io/name instead (the Kustomization that created the
# HelmRelease is one hop further removed and isn't labeled onto the Deployment).
#
# For a Helm-based app, the PVC itself is a plain manifest owned by a
# *different* Flux Kustomization than the HelmRelease (the app's own
# base/kustomization.yaml applies both as siblings) -- resuming the
# HelmRelease alone does nothing for the deleted PVC, which otherwise waits
# for that Kustomization's own reconcile interval (up to 1h) to notice it's
# missing and recreate it. So the PVC's owning Kustomization (read from its
# own labels before deletion) is always force-reconciled too, regardless of
# which kind of object owns the Deployment.
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
# Parses -e/--environment, -n/--namespace and --deploy; the first bare (non-flag) argument is the app name.
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

# -e/--environment must resolve to a real "admin@<env>-homelab" kubecontext (see CTX below) - unlike
# kopiur-list.sh/kopiur-create.sh, there's no "fall back to whatever context is current" mode here, since
# a restore is destructive enough that the target cluster should always be named explicitly.
validate_environment "${ENV}"

if [ -z "${NS}" ]; then
    just log fatal "-n/--namespace is required"
    exit 1
fi

if [ -z "${APP}" ]; then
    just log error "app name is required"
    usage
fi

# DEPLOY defaults to the app name, since that's true for the overwhelming majority of apps; --deploy only
# needs to be passed when a chart names its Deployment differently from the app/release name.
DEPLOY="${DEPLOY:-${APP}}"
CTX=$(kubecontext_for_environment "${ENV}")

if ! kubectl --context "${CTX}" get pvc "${APP}" -n "${NS}" >/dev/null 2>&1; then
    just log fatal "PVC not found" "app" "${APP}" "namespace" "${NS}"
    exit 1
fi

if ! kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" >/dev/null 2>&1; then
    just log fatal "Deployment not found (pass --deploy if the deployment name differs from the app name)" "deployment" "${DEPLOY}" "namespace" "${NS}"
    exit 1
fi

# Captured up front so step 5 can scale back to exactly what it was, rather than a hardcoded 1 - restoring
# a PVC shouldn't also silently reset an app that was deliberately scaled to e.g. 2+ replicas.
ORIG_REPLICAS=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.spec.replicas}')

# Determines which kind of Flux object owns the Deployment (see header comment) - exactly one of HR/KS ends
# up non-empty, and that's what the suspend/resume branch below acts on.
HR=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/name}' 2>/dev/null || true)
KS=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.kustomize\.toolkit\.fluxcd\.io/name}' 2>/dev/null || true)

# The PVC's own owning Kustomization, read before it's deleted below (its labels naturally disappear along
# with it) - needed for the Helm-based case (see header comment), where it can differ from KS above.
PVC_KS=$(kubectl --context "${CTX}" get pvc "${APP}" -n "${NS}" -o jsonpath='{.metadata.labels.kustomize\.toolkit\.fluxcd\.io/name}' 2>/dev/null || true)
PVC_KS_NS=$(kubectl --context "${CTX}" get pvc "${APP}" -n "${NS}" -o jsonpath='{.metadata.labels.kustomize\.toolkit\.fluxcd\.io/namespace}' 2>/dev/null || true)
PVC_KS_NS="${PVC_KS_NS:-flux-system}"

# Suspends whichever Flux object owns the Deployment, so it can't fight the manual scale-down/PVC-delete
# steps below, and defines `resume` (called in step 4) to resume that same object afterward.
if [ -n "${HR}" ]; then
    HR_NS=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/namespace}')
    just log info "Suspending HelmRelease" "step" "1/6" "helmrelease" "${HR}" "namespace" "${HR_NS}"
    flux --context "${CTX}" suspend helmrelease "${HR}" -n "${HR_NS}"
    resume() {
        flux --context "${CTX}" resume helmrelease "${HR}" -n "${HR_NS}"
    }
elif [ -n "${KS}" ]; then
    just log info "Suspending Kustomization" "step" "1/6" "kustomization" "${KS}"
    flux --context "${CTX}" suspend kustomization "${KS}"
    resume() {
        flux --context "${CTX}" resume kustomization "${KS}"
    }
else
    just log fatal "could not determine the owning Flux object for this deployment (no helm.toolkit.fluxcd.io/name or kustomize.toolkit.fluxcd.io/name label -- is it managed by Flux at all?)" "namespace" "${NS}" "deployment" "${DEPLOY}"
    exit 1
fi

# Scaling to 0 (rather than deleting the Deployment) and waiting for its pods to actually terminate is what
# lets the PVC below be deleted cleanly - a still-mounted PVC can't be deleted.
just log info "Scaling down" "step" "2/6" "deployment" "${DEPLOY}" "namespace" "${NS}"
kubectl --context "${CTX}" scale deployment "${DEPLOY}" -n "${NS}" --replicas=0
kubectl --context "${CTX}" wait pod -l app="${APP}" -n "${NS}" --for=delete --timeout=120s 2>/dev/null || true

# Both the PVC and its Restore object must go together (see header comment) so kopiur re-resolves a fresh
# snapshot on recreation instead of reusing whatever it pinned the first time.
just log info "Deleting PVC and Restore object" "step" "3/6" "app" "${APP}" "namespace" "${NS}"
kubectl --context "${CTX}" delete pvc "${APP}" -n "${NS}" --wait=true
kubectl --context "${CTX}" delete restore "${APP}" -n "${NS}" --wait=true

# Resumes the HelmRelease/Kustomization suspended in step 1, then, for the Helm-based case, also
# force-reconciles the PVC's own owning Kustomization (see header comment) since resuming the HelmRelease
# alone doesn't touch it.
just log info "Resuming" "step" "4/6" "deployment" "${DEPLOY}"
resume
if [ -n "${PVC_KS}" ] && [ "${PVC_KS}" != "${KS}" ]; then
    # Only needs to trigger the reconcile, not block on flux's own --wait
    # (which times out on this Kustomization's full health check well before
    # the actual apply -- the PVC and Restore recreation we care about -- has
    # happened); step 6 below polls for the real success signal (PVC Bound).
    flux --context "${CTX}" reconcile kustomization "${PVC_KS}" -n "${PVC_KS_NS}" || true
fi

# Resuming Flux does not reliably bring a Helm-based Deployment back to its
# original replica count (see header comment) -- scale it back up explicitly
# rather than trust that. Doing this BEFORE waiting for the PVC to bind is
# required either way: its StorageClass is WaitForFirstConsumer, so it only
# binds once a pod tries to mount it, and nothing schedules that pod while
# replicas is still 0.
just log info "Scaling back up" "step" "5/6" "deployment" "${DEPLOY}" "replicas" "${ORIG_REPLICAS}"
kubectl --context "${CTX}" scale deployment "${DEPLOY}" -n "${NS}" --replicas="${ORIG_REPLICAS}"

# Polls up to 5 minutes (60 * 5s) for the recreated PVC to reach Bound - the real signal that the populator
# finished restoring from the snapshot, since neither `flux resume`/`reconcile` nor `kubectl scale` above
# block on that.
just log info "Waiting for the new PVC to bind (populating from the latest snapshot)" "step" "6/6"
PHASE=""
for _ in $(seq 1 60); do
    PHASE=$(kubectl --context "${CTX}" get pvc "${APP}" -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [ "${PHASE}" = "Bound" ] && break
    just log debug "waiting for PVC to bind" "phase" "${PHASE:-Pending}"
    sleep 5
done

if [ "${PHASE}" != "Bound" ]; then
    just log fatal "PVC did not reach Bound within the timeout -- check manually" "last_phase" "${PHASE:-unknown}"
    exit 1
fi

just log info "Done."
