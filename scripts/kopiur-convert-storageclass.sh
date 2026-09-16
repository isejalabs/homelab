#!/bin/sh
# Converts an existing kopiur-managed PVC (created via apps/storage/pvc or
# pvc-no-backup) onto a different StorageClass in place -- e.g. ext4 -> xfs
# for #133 (MongoDB/WiredTiger recommends XFS). Longhorn can't reformat a
# live volume and storageClassName is immutable on a PVC, so this copies the
# data onto a fresh PVC on the new StorageClass, then rebinds that PV under
# the ORIGINAL PVC's name -- the standard k8s "release and rebind a PV"
# recipe, the dynamic-Longhorn analogue of this repo's static proxmox-csi PV
# bindings (see docs/architecture/storage.md). Keeping the original name is
# required because apps/storage/pvc ties Restore/SnapshotPolicy/
# SnapshotSchedule/ExternalSecret all to the same ${APP} name.
#
# Land the STORAGE_CLASS (and, for apps/storage/pvc, STORAGE_STAGING_CLASS)
# override in the app's flux/ks.yaml first -- see docs/app-storage.md -- so
# that once the Kustomization/HelmRelease is resumed afterwards, its desired
# state already matches the PVC this script hand-built and Flux has nothing
# to reconcile.
set -eu

usage() {
    echo "Usage: $(basename "$0") -e <env> -n <ns> --storage-class <new-sc> [--deploy <name>] [--uid <uid>] [--gid <gid>] <pvc-name>" >&2
    exit 1
}

PVC=""
ENV=""
NS=""
NEW_SC=""
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
        --storage-class)
            NEW_SC="$2"
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
            PVC="$1"
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
[ -z "${NEW_SC}" ] && {
    just log fatal "--storage-class is required"
    exit 1
}
[ -z "${PVC}" ] && {
    just log error "pvc name is required"
    usage
}

DEPLOY="${DEPLOY:-${PVC}}"
CTX="admin@${ENV}-homelab"

if ! kubectl --context "${CTX}" get pvc "${PVC}" -n "${NS}" >/dev/null 2>&1; then
    just log fatal "PVC not found" "pvc" "${PVC}" "namespace" "${NS}"
    exit 1
fi

CUR_SC=$(kubectl --context "${CTX}" get pvc "${PVC}" -n "${NS}" -o jsonpath='{.spec.storageClassName}')
if [ "${CUR_SC}" = "${NEW_SC}" ]; then
    just log fatal "PVC is already on this StorageClass" "pvc" "${PVC}" "storageClass" "${NEW_SC}"
    exit 1
fi
SIZE=$(kubectl --context "${CTX}" get pvc "${PVC}" -n "${NS}" -o jsonpath='{.spec.resources.requests.storage}')
ACCESS_MODE=$(kubectl --context "${CTX}" get pvc "${PVC}" -n "${NS}" -o jsonpath='{.spec.accessModes[0]}')
HAS_DATASOURCE=$(kubectl --context "${CTX}" get pvc "${PVC}" -n "${NS}" -o jsonpath='{.spec.dataSourceRef.name}' 2>/dev/null || true)

if ! kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" >/dev/null 2>&1; then
    just log fatal "Deployment not found (pass --deploy if it differs from the PVC name)" "deployment" "${DEPLOY}" "namespace" "${NS}"
    exit 1
fi

HR=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/name}' 2>/dev/null || true)
KS=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.kustomize\.toolkit\.fluxcd\.io/name}' 2>/dev/null || true)

if [ -n "${HR}" ]; then
    HR_NS=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/namespace}')
    just log info "Suspending HelmRelease" "step" "1/6" "helmrelease" "${HR}" "namespace" "${HR_NS}"
    flux --context "${CTX}" suspend helmrelease "${HR}" -n "${HR_NS}"
elif [ -n "${KS}" ]; then
    just log info "Suspending Kustomization" "step" "1/6" "kustomization" "${KS}"
    flux --context "${CTX}" suspend kustomization "${KS}"
else
    just log fatal "could not determine the owning Flux object for this deployment" "namespace" "${NS}" "deployment" "${DEPLOY}"
    exit 1
fi

just log info "Scaling down" "step" "2/6" "deployment" "${DEPLOY}" "namespace" "${NS}"
kubectl --context "${CTX}" scale deployment "${DEPLOY}" -n "${NS}" --replicas=0
kubectl --context "${CTX}" wait pod -l app="${DEPLOY}" -n "${NS}" --for=delete --timeout=120s 2>/dev/null || true

TMP_PVC="${PVC}-newsc"
just log info "Provisioning staging PVC on the new StorageClass" "step" "3/6" "pvc" "${TMP_PVC}" "storageClass" "${NEW_SC}"
kubectl --context "${CTX}" delete pvc "${TMP_PVC}" -n "${NS}" --ignore-not-found --wait=true
kubectl --context "${CTX}" apply -n "${NS}" -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${TMP_PVC}
spec:
  accessModes: ["${ACCESS_MODE}"]
  resources:
    requests:
      storage: ${SIZE}
  storageClassName: ${NEW_SC}
EOF

JOB="${TMP_PVC}-migrate"
# Longhorn volumes aren't node-pinned the way proxmox-csi ones are, but keep
# the copy job on the app's own node/zone anyway -- cheap insurance against
# any topology constraint and consistent with kopiur-migrate-pvc.sh.
NODE_SELECTOR=$(kubectl --context "${CTX}" get deployment "${DEPLOY}" -n "${NS}" -o jsonpath='{.spec.template.spec.nodeSelector}' 2>/dev/null || true)
NODE_SELECTOR="${NODE_SELECTOR:-{\}}"

just log info "Running copy job" "step" "4/6" "job" "${JOB}" "from" "${PVC}" "to" "${TMP_PVC}" "uid" "${UID_}" "gid" "${GID_}"
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
            claimName: ${PVC}
        - name: new
          persistentVolumeClaim:
            claimName: ${TMP_PVC}
EOF
kubectl --context "${CTX}" wait job "${JOB}" -n "${NS}" --for=condition=complete --timeout=300s
kubectl --context "${CTX}" logs job/"${JOB}" -n "${NS}"
kubectl --context "${CTX}" delete job "${JOB}" -n "${NS}" --wait=true

TMP_PV=$(kubectl --context "${CTX}" get pvc "${TMP_PVC}" -n "${NS}" -o jsonpath='{.spec.volumeName}')
just log info "Rebinding the new volume under the original PVC name" "step" "5/6" "pv" "${TMP_PV}" "pvc" "${PVC}"

kubectl --context "${CTX}" delete pvc "${TMP_PVC}" -n "${NS}" --wait=true
kubectl --context "${CTX}" patch pv "${TMP_PV}" --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'

just log info "Deleting old PVC (its PV is left Released, not deleted, as a safety net)" "pvc" "${PVC}"
kubectl --context "${CTX}" delete pvc "${PVC}" -n "${NS}" --wait=true

DATASOURCE_YAML=""
if [ -n "${HAS_DATASOURCE}" ]; then
    DATASOURCE_YAML="
  dataSourceRef:
    apiGroup: kopiur.home-operations.com
    kind: Restore
    name: ${PVC}"
fi

kubectl --context "${CTX}" apply -n "${NS}" -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC}
spec:
  accessModes: ["${ACCESS_MODE}"]
  volumeName: ${TMP_PV}
  storageClassName: ${NEW_SC}
  resources:
    requests:
      storage: ${SIZE}${DATASOURCE_YAML}
EOF
kubectl --context "${CTX}" wait pvc "${PVC}" -n "${NS}" --for=jsonpath='{.status.phase}'=Bound --timeout=60s

just log info "Triggering manual kopiur snapshot" "step" "6/6" "app" "${PVC}"
SNAP=$(kubectl --context "${CTX}" create -n "${NS}" -f - -o jsonpath='{.metadata.name}' <<EOF
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Snapshot
metadata:
  generateName: ${PVC}-convert-
  namespace: ${NS}
spec:
  policyRef:
    name: ${PVC}
  description: "StorageClass conversion to ${NEW_SC}"
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
    just log fatal "snapshot did not succeed -- check manually before resuming" "snapshot" "${SNAP}" "last_phase" "${PHASE:-unknown}"
    exit 1
fi

just log info "Volume converted to ${NEW_SC} and snapshotted. Deployment left suspended+scaled to 0" "step" "done"
just log info "Next: resume the Kustomization/HelmRelease (its desired state should now match) and scale ${DEPLOY} back up."
