#!/bin/sh

set -eu

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# The literal spec.sync.path each env's k8s/infra/flux-system/flux-instance/envs/<env>/helmrelease.yaml
# points the real cluster at - not an arbitrary top-level kustomize target.
ENVS='dbg dev head poc prod qa rebuild src'

status=0

for env in $ENVS; do
    dir="k8s/bootstrap/cluster/flux/envs/$env"

    if ! flate test all --path "$dir"; then
        printf "${RED}flate test failed: %s${NC}\n" "$dir"
        status=1
        continue
    fi

    printf "${GREEN}OK: %s${NC}\n" "$dir"
done

exit $status
