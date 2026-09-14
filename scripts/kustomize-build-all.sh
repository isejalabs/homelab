#!/bin/bash

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# SealedSecret's community schema forbids `spec.template.metadata.creationTimestamp`, which every
# kubeseal-generated manifest sets to null as part of ObjectMeta - a schema-catalog inaccuracy, not
# a real problem with our manifests, so its schema validation is skipped rather than worked around.
SKIP_KINDS='SealedSecret'

K8S_VERSION=$(grep -oP 'K8S_VERSION="\K[^"]+' scripts/upgrade-k8s.sh)

status=0

while IFS= read -r -d '' kustomization; do
    dir=$(dirname "$kustomization")

    # k8s/components/* are kustomize Components, meant to be pulled in via `components:` by the
    # overlays under envs/ that this loop already builds - they can't be built standalone.
    case "$dir" in k8s/components/*) continue ;; esac

    if ! manifests=$(kubectl kustomize "$dir" 2>&1); then
        echo -e "${RED}kustomize build failed: $dir${NC}"
        echo "$manifests"
        status=1
        continue
    fi

    if ! echo "$manifests" | kubeconform -strict -ignore-missing-schemas -skip "$SKIP_KINDS" \
        -kubernetes-version "$K8S_VERSION" \
        -schema-location default \
        -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
        -summary; then
        echo -e "${RED}kubeconform failed: $dir${NC}"
        status=1
        continue
    fi

    echo -e "${GREEN}OK: $dir${NC}"
done < <(find k8s -name kustomization.yaml -print0)

exit $status
