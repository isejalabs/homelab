# shellcheck shell=bash
# Shared helpers for the longhorn-snapshot-*.sh scripts. Sourced after lib/common.sh, bash only (uses arrays).
# Expects the caller to have set CTX_ARGS (an array: empty, or `--context <ctx>`) like kopiur-create.sh does.
# (Array expansions use the ${a[@]+"${a[@]}"} form: an empty array is "unbound" under `set -u` on bash 3.2.)

# Prints one "<volume> <namespace> <pvc>" line per Longhorn volume that is bound to a PVC in scope: all
# namespaces when $1 is "-A", otherwise only namespace $1; $2, if given, narrows to that one PVC name.
# Longhorn volumes are named after the PV (pvc-<uid>), so this volumes.longhorn.io status is the one place
# that maps a PVC to the volume its Snapshot CRs hang off.
longhorn_volumes() {
    local ns="$1" pvc="${2:-}"
    kubectl ${CTX_ARGS[@]+"${CTX_ARGS[@]}"} -n longhorn-system get volumes.longhorn.io \
        -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.kubernetesStatus.namespace}{" "}{.status.kubernetesStatus.pvcName}{"\n"}{end}' |
        awk -v ns="${ns}" -v pvc="${pvc}" 'NF == 3 && (ns == "-A" || $2 == ns) && (pvc == "" || $3 == pvc)'
}

# Prints "<name> <creationTime>" of the Longhorn snapshot of volume $1 to restore from, considering only
# snapshots that are ready and not marked for removal: $2 (if non-empty) is an exact snapshot name,
# otherwise $3 (if non-empty) is an RFC3339 UTC timestamp and the newest snapshot created at or before it is
# picked (lexical comparison is valid for same-format UTC timestamps), otherwise the newest overall.
# Prints nothing if no snapshot matches.
longhorn_pick_snapshot() {
    local volume="$1" name="${2:-}" at="${3:-}"
    kubectl ${CTX_ARGS[@]+"${CTX_ARGS[@]}"} -n longhorn-system get snapshots.longhorn.io -l "longhornvolume=${volume}" \
        -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.creationTime}{" "}{.status.readyToUse}{" "}{.status.markRemoved}{"\n"}{end}' |
        awk -v name="${name}" -v at="${at}" '
            $3 == "true" && $4 != "true" && (name == "" || $1 == name) && (at == "" || $2 <= at) { print $2, $1 }' |
        sort -r | head -n 1 | awk '{ print $2, $1 }'
}

# Prints the current .status.state of Longhorn volume $1 (e.g. attached, detached).
longhorn_volume_state() {
    kubectl ${CTX_ARGS[@]+"${CTX_ARGS[@]}"} -n longhorn-system get volumes.longhorn.io "$1" -o jsonpath='{.status.state}'
}
