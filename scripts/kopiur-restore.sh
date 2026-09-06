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

CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

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
        -e | --env)
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

DEPLOY="${DEPLOY:-${APP}}"
CTX="admin@${ENV}-homelab"

if ! kubectl --context "${CTX}" get pvc "${APP}" -n "${NS}" >/dev/null 2>&1; then
    printf "${RED}ERROR: PVC '%s' not found in namespace '%s'${NC}\n" "${APP}" "${NS}" >&2
    exit 1
fi

if ! kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" >/dev/null 2>&1; then
    printf "${RED}ERROR: Deployment '%s' not found in namespace '%s' (pass --deploy if the deployment name differs from the app name)${NC}\n" "${DEPLOY}" "${NS}" >&2
    exit 1
fi

ORIG_REPLICAS=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.spec.replicas}')

HR=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/name}' 2>/dev/null || true)
KS=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.kustomize\.toolkit\.fluxcd\.io/name}' 2>/dev/null || true)

PVC_KS=$(kubectl --context "${CTX}" get pvc "${APP}" -n "${NS}" -o jsonpath='{.metadata.labels.kustomize\.toolkit\.fluxcd\.io/name}' 2>/dev/null || true)
PVC_KS_NS=$(kubectl --context "${CTX}" get pvc "${APP}" -n "${NS}" -o jsonpath='{.metadata.labels.kustomize\.toolkit\.fluxcd\.io/namespace}' 2>/dev/null || true)
PVC_KS_NS="${PVC_KS_NS:-flux-system}"

if [ -n "${HR}" ]; then
    HR_NS=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/namespace}')
    printf "${CYAN}[1/6] Suspending HelmRelease %s in %s...${NC}\n" "${HR}" "${HR_NS}"
    flux --context "${CTX}" suspend helmrelease "${HR}" -n "${HR_NS}"
    resume() {
        flux --context "${CTX}" resume helmrelease "${HR}" -n "${HR_NS}"
    }
elif [ -n "${KS}" ]; then
    printf "${CYAN}[1/6] Suspending Kustomization %s...${NC}\n" "${KS}"
    flux --context "${CTX}" suspend kustomization "${KS}"
    resume() {
        flux --context "${CTX}" resume kustomization "${KS}"
    }
else
    printf "${RED}ERROR: could not determine the owning Flux object for deployment %s/%s${NC}\n" "${NS}" "${DEPLOY}" >&2
    printf "${RED}(no helm.toolkit.fluxcd.io/name or kustomize.toolkit.fluxcd.io/name label -- is it managed by Flux at all?)${NC}\n" >&2
    exit 1
fi

printf "${CYAN}[2/6] Scaling down %s in %s...${NC}\n" "${DEPLOY}" "${NS}"
kubectl --context "${CTX}" scale deployment "${DEPLOY}" -n "${NS}" --replicas=0
kubectl --context "${CTX}" wait pod -l app="${APP}" -n "${NS}" --for=delete --timeout=120s 2>/dev/null || true

printf "${CYAN}[3/6] Deleting PVC and Restore object for %s in %s...${NC}\n" "${APP}" "${NS}"
kubectl --context "${CTX}" delete pvc "${APP}" -n "${NS}" --wait=true
kubectl --context "${CTX}" delete restore "${APP}" -n "${NS}" --wait=true

printf "${CYAN}[4/6] Resuming %s...${NC}\n" "${DEPLOY}"
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
printf "${CYAN}[5/6] Scaling %s back up to %s replica(s)...${NC}\n" "${DEPLOY}" "${ORIG_REPLICAS}"
kubectl --context "${CTX}" scale deployment "${DEPLOY}" -n "${NS}" --replicas="${ORIG_REPLICAS}"

printf "${CYAN}[6/6] Waiting for the new PVC to bind (populating from the latest snapshot)...${NC}\n"
PHASE=""
for _ in $(seq 1 60); do
    PHASE=$(kubectl --context "${CTX}" get pvc "${APP}" -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [ "${PHASE}" = "Bound" ] && break
    echo "  status: ${PHASE:-Pending}"
    sleep 5
done

if [ "${PHASE}" != "Bound" ]; then
    printf "${YELLOW}WARNING: PVC did not reach Bound within the timeout (last phase: %s) -- check manually${NC}\n" "${PHASE:-unknown}"
    exit 1
fi

printf "${GREEN}Done.${NC}\n"
