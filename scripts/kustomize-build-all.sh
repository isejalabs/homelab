#!/bin/sh
# Runs `kubectl kustomize` + kubeconform against every kustomize overlay under k8s/ (except the
# non-standalone Components under k8s/components/), to catch a broken build or schema-invalid manifest
# before Flux hits it for real.
#
# Usage: scripts/kustomize-build-all.sh
# Takes no arguments; run from the repo root (invoked by the kustomize-build CI workflow).

set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

# SealedSecret's community schema forbids `spec.template.metadata.creationTimestamp`, which every
# kubeseal-generated manifest sets to null as part of ObjectMeta - a schema-catalog inaccuracy, not
# a real problem with our manifests, so its schema validation is skipped rather than worked around.
SKIP_KINDS='SealedSecret'

# Read from upgrade-k8s.sh (the single source of truth for the cluster's target k8s version) rather than
# duplicating the version number here, so the two never drift out of sync.
K8S_VERSION=$(grep -oP 'K8S_VERSION="\K[^"]+' scripts/upgrade-k8s.sh)

# Listed into a file rather than piped into the while loop below, so the loop runs in the
# current shell (not a subshell) and `status` set inside it is still visible at `exit $status`.
list=$(mktemp)
trap 'rm -f "$list"' EXIT
find k8s -name kustomization.yaml > "$list"

status=0

# Builds and validates every overlay, tracking the worst exit status across all of them rather than bailing
# on the first failure, so one bad overlay doesn't hide problems in the rest.
while IFS= read -r kustomization; do
    dir=$(dirname "$kustomization")

    # k8s/components/* are kustomize Components, meant to be pulled in via `components:` by the
    # overlays under envs/ that this loop already builds - they can't be built standalone.
    case "$dir" in k8s/components/*) continue ;; esac

    if ! manifests=$(kubectl kustomize "$dir" 2>&1); then
        log_debug_output "$manifests"
        just log error "kustomize build failed" "unit" "$dir"
        status=1
        continue
    fi

    if ! echo "$manifests" | kubeconform -strict -ignore-missing-schemas -skip "$SKIP_KINDS" \
        -kubernetes-version "$K8S_VERSION" \
        -schema-location default \
        -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
        -summary; then
        just log error "kubeconform failed" "unit" "$dir"
        status=1
        continue
    fi

    just log info "OK" "unit" "$dir"
done < "$list"

exit $status
