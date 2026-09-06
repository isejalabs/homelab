#!/bin/bash
# Restores an app's PVC from its latest kopiur snapshot.
#
# kopiur's Restore CR populates a PVC only once, at creation (it's a CSI
# populator, not a continuous sync target like VolSync's ReplicationDestination)
# -- so "restoring" means deleting the PVC and letting a fresh one populate,
# not patching a field on an existing volume.
#
# Flux actively reverts manual changes (a scaled-down Deployment gets scaled
# back up on the next reconcile), so the owning Flux object must be suspended
# first. Which kind of object owns a Deployment is detected from Flux's own
# provenance labels: a plain-manifest app carries
# kustomize.toolkit.fluxcd.io/name directly; a Helm-based app carries
# helm.toolkit.fluxcd.io/name instead (the Kustomization that created the
# HelmRelease is one hop further removed and isn't labeled onto the Deployment).
set -euo pipefail

CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

APP="$1"
NS="${2:-$(kubectl config view --minify -o jsonpath='{..namespace}')}"
DEPLOY="${3:-${APP}}"

if [ -z "${NS}" ]; then
    echo -e "${RED}ERROR: no namespace given and no default namespace set in the current kubeconfig context${NC}" >&2
    exit 1
fi

if ! kubectl get pvc "${APP}" -n "${NS}" &>/dev/null; then
    echo -e "${RED}ERROR: PVC '${APP}' not found in namespace '${NS}'${NC}" >&2
    exit 1
fi

if ! kubectl get deployment "${DEPLOY}" -n "${NS}" &>/dev/null; then
    echo -e "${RED}ERROR: Deployment '${DEPLOY}' not found in namespace '${NS}' (pass a 3rd argument if the deployment name differs from the app name)${NC}" >&2
    exit 1
fi

HR=$(kubectl get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/name}' 2>/dev/null || true)
KS=$(kubectl get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.kustomize\.toolkit\.fluxcd\.io/name}' 2>/dev/null || true)

if [ -n "${HR}" ]; then
    HR_NS=$(kubectl get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/namespace}')
    echo -e "${CYAN}[1/5] Suspending HelmRelease ${HR} in ${HR_NS}...${NC}"
    flux suspend helmrelease "${HR}" -n "${HR_NS}"
    resume() {
        flux resume helmrelease "${HR}" -n "${HR_NS}"
        flux reconcile helmrelease "${HR}" -n "${HR_NS}" --with-source --force
    }
elif [ -n "${KS}" ]; then
    echo -e "${CYAN}[1/5] Suspending Kustomization ${KS}...${NC}"
    flux suspend kustomization "${KS}"
    resume() {
        flux resume kustomization "${KS}"
        flux reconcile kustomization "${KS}"
    }
else
    echo -e "${RED}ERROR: could not determine the owning Flux object for deployment ${NS}/${DEPLOY}" >&2
    echo -e "${RED}(no helm.toolkit.fluxcd.io/name or kustomize.toolkit.fluxcd.io/name label -- is it managed by Flux at all?)${NC}" >&2
    exit 1
fi

echo -e "${CYAN}[2/5] Scaling down ${DEPLOY} in ${NS}...${NC}"
kubectl scale deployment "${DEPLOY}" -n "${NS}" --replicas=0
kubectl wait pod -l app="${APP}" -n "${NS}" --for=delete --timeout=120s 2>/dev/null || true

echo -e "${CYAN}[3/5] Deleting PVC ${APP} in ${NS}...${NC}"
kubectl delete pvc "${APP}" -n "${NS}" --wait=true

# The PVC's StorageClass is WaitForFirstConsumer, so it only binds once a pod
# tries to mount it -- and nothing recreates that pod (or the PVC itself)
# until Flux is resumed. Resume BEFORE waiting for Bound, not after, or this
# hangs forever waiting on a pod that will never exist.
echo -e "${CYAN}[4/5] Resuming (recreates the PVC and scales the app back up)...${NC}"
resume

echo -e "${CYAN}[5/5] Waiting for the new PVC to bind (populating from the latest snapshot)...${NC}"
PHASE=""
for _ in $(seq 1 60); do
    PHASE=$(kubectl get pvc "${APP}" -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [ "${PHASE}" = "Bound" ] && break
    echo "  status: ${PHASE:-Pending}"
    sleep 5
done

if [ "${PHASE}" != "Bound" ]; then
    echo -e "${YELLOW}WARNING: PVC did not reach Bound within the timeout (last phase: ${PHASE:-unknown}) -- check manually${NC}"
    exit 1
fi

echo -e "${GREEN}Done.${NC}"
