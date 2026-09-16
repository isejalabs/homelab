#!/bin/sh
# Copies an app's data from an old PVC onto a new kopiur-managed PVC, ahead of
# a claimName/existingClaim cut-over commit. Generic across apps -- see
# docs/kopiur-backup-restore.md and #1205 (actualbudget, the pilot) / #1263
# for the lessons folded in here.
#
# - Runs the copy Job as the target uid/gid rather than trying to preserve
#   the source files' original ownership: `cp -a`/`cp -p` under `set -e`
#   fails when the copying process doesn't own the source uid (hit during
#   actualbudget's qa UAT, where qa started clean at uid 1000 copying from
#   uid-1001-owned source data). Plain `cp -rv` sidesteps this -- files it
#   writes are owned by whichever uid/gid the Job's securityContext runs as,
#   same as the target app will run as.
# - Suspends the Deployment's owning Flux object first, same as
#   kopiur-restore.sh, so Flux doesn't fight the manual scale-down while the
#   copy is in flight. Left suspended and scaled to 0 on exit -- resuming and
#   scaling back up is a separate step, done once the cut-over
#   (claimName/existingClaim -> the new PVC) has actually been applied.
set -eu

usage() {
    echo "Usage: $(basename "$0") -e <env> -n <ns> --old-pvc <name> [--deploy <name>] [--uid <uid>] [--gid <gid>] <new-pvc>" >&2
    exit 1
}

NEW_PVC=""
ENV=""
NS=""
OLD_PVC=""
DEPLOY=""
UID_="1000"
GID_="1000"
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
        --old-pvc)
            OLD_PVC="$2"
            shift 2
            ;;
        --deploy)
            DEPLOY="$2"
            shift 2
            ;;
        --uid)
            UID_="$2"
            shift 2
            ;;
        --gid)
            GID_="$2"
            shift 2
            ;;
        -h | --help) usage ;;
        -*)
            just log error "unknown flag" "flag" "$1"
            usage
            ;;
        *)
            NEW_PVC="$1"
            shift
            ;;
    esac
done

case "${ENV}" in
    dbg | dev | head | poc | prod | qa | rebuild | src) ;;
    *)
        just log fatal "-e/--environment must be one of dbg|dev|head|poc|prod|qa|rebuild|src" "got" "${ENV}"
        exit 1
        ;;
esac

[ -z "${NS}" ] && {
    just log fatal "-n/--namespace is required"
    exit 1
}
[ -z "${OLD_PVC}" ] && {
    just log fatal "--old-pvc is required"
    exit 1
}
[ -z "${NEW_PVC}" ] && {
    just log error "new PVC name is required"
    usage
}

DEPLOY="${DEPLOY:-${NEW_PVC}}"
CTX="admin@${ENV}-homelab"

if ! kubectl --context "${CTX}" get pvc "${OLD_PVC}" -n "${NS}" >/dev/null 2>&1; then
    just log fatal "old PVC not found" "pvc" "${OLD_PVC}" "namespace" "${NS}"
    exit 1
fi

if ! kubectl --context "${CTX}" get pvc "${NEW_PVC}" -n "${NS}" >/dev/null 2>&1; then
    just log fatal "new PVC not found -- deploy the apps/storage/pvc wiring commit first" "pvc" "${NEW_PVC}" "namespace" "${NS}"
    exit 1
fi

if ! kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" >/dev/null 2>&1; then
    just log fatal "Deployment not found (pass --deploy if it differs from the new PVC name)" "deployment" "${DEPLOY}" "namespace" "${NS}"
    exit 1
fi

HR=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/name}' 2>/dev/null || true)
KS=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.kustomize\.toolkit\.fluxcd\.io/name}' 2>/dev/null || true)

if [ -n "${HR}" ]; then
    HR_NS=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/namespace}')
    just log info "Suspending HelmRelease" "step" "1/5" "helmrelease" "${HR}" "namespace" "${HR_NS}"
    flux --context "${CTX}" suspend helmrelease "${HR}" -n "${HR_NS}"
elif [ -n "${KS}" ]; then
    just log info "Suspending Kustomization" "step" "1/5" "kustomization" "${KS}"
    flux --context "${CTX}" suspend kustomization "${KS}"
else
    just log fatal "could not determine the owning Flux object for this deployment" "namespace" "${NS}" "deployment" "${DEPLOY}"
    exit 1
fi

just log info "Scaling down" "step" "2/5" "deployment" "${DEPLOY}" "namespace" "${NS}"
kubectl --context "${CTX}" scale deployment "${DEPLOY}" -n "${NS}" --replicas=0
kubectl --context "${CTX}" wait pod -l app="${DEPLOY}" -n "${NS}" --for=delete --timeout=120s 2>/dev/null || true

JOB="${NEW_PVC}-migrate"
# Some old PVCs (proxmox-csi) are pinned to a specific node/zone and can't
# be attached anywhere else -- schedule the copy job the same place the app
# itself runs, or the attach hangs/fails outright trying to move the disk.
NODE_SELECTOR=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.spec.template.spec.nodeSelector}' 2>/dev/null || true)
NODE_SELECTOR="${NODE_SELECTOR:-{\}}"

just log info "Running copy job" "step" "3/5" "job" "${JOB}" "from" "${OLD_PVC}" "to" "${NEW_PVC}" "uid" "${UID_}" "gid" "${GID_}"
kubectl --context "${CTX}" delete job "${JOB}" -n "${NS}" --ignore-not-found --wait=true
kubectl --context "${CTX}" apply -n "${NS}" -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB}
  namespace: ${NS}
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      nodeSelector: ${NODE_SELECTOR}
      securityContext:
        runAsUser: ${UID_}
        runAsGroup: ${GID_}
        fsGroup: ${GID_}
      containers:
        - name: migrate
          image: docker.io/library/busybox:stable
          command: ["sh", "-c", "cp -rv /old/. /new/"]
          volumeMounts:
            - name: old
              mountPath: /old
              readOnly: true
            - name: new
              mountPath: /new
      volumes:
        - name: old
          persistentVolumeClaim:
            claimName: ${OLD_PVC}
        - name: new
          persistentVolumeClaim:
            claimName: ${NEW_PVC}
EOF
kubectl --context "${CTX}" wait job "${JOB}" -n "${NS}" --for=condition=complete --timeout=300s
kubectl --context "${CTX}" logs job/"${JOB}" -n "${NS}"
kubectl --context "${CTX}" delete job "${JOB}" -n "${NS}" --wait=true

just log info "Triggering manual kopiur snapshot" "step" "4/5" "app" "${NEW_PVC}"
SNAP=$(kubectl --context "${CTX}" create -n "${NS}" -f - -o jsonpath='{.metadata.name}' <<EOF
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Snapshot
metadata:
  generateName: ${NEW_PVC}-migrate-
  namespace: ${NS}
spec:
  policyRef:
    name: ${NEW_PVC}
  description: "migration from ${OLD_PVC}"
EOF
)

PHASE=""
for _ in $(seq 1 60); do
    PHASE=$(kubectl --context "${CTX}" get snapshot "${SNAP}" -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [ "${PHASE}" = "Succeeded" ] && break
    [ "${PHASE}" = "Failed" ] && break
    just log debug "waiting for snapshot" "phase" "${PHASE:-Pending}"
    sleep 5
done

if [ "${PHASE}" != "Succeeded" ]; then
    just log fatal "snapshot did not succeed -- check manually before cutting over" "snapshot" "${SNAP}" "last_phase" "${PHASE:-unknown}"
    exit 1
fi

just log info "Data copied and first snapshot taken. Deployment left suspended+scaled to 0" "step" "5/5"
just log info "Next: apply the cut-over (point ${DEPLOY} at PVC ${NEW_PVC}), then resume and scale back up."
