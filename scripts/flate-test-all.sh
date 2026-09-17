#!/bin/sh
# Runs `flate test all` (home-operations/flate) against every environment's top-level Flux sync target, to
# catch a Flux Kustomization pointing at a path/name that doesn't actually exist anywhere in the tree.
#
# Usage: scripts/flate-test-all.sh
# Takes no arguments; run from the repo root (invoked by the flate-test-all CI workflow).

set -eu

# home-operations/flate/action sets FLATE_BASE (default: the repo's default branch) to enable its
# changed-only mode. This check always validates the full tree per env, not just a PR's diff, so unset it.
unset FLATE_BASE

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# The literal spec.sync.path each env's k8s/infra/flux-system/flux-instance/envs/<env>/helmrelease.yaml
# points the real cluster at - not an arbitrary top-level kustomize target.
ENVS='dbg dev head poc prod qa rebuild src'

status=0

# Runs flate against each env's sync target in turn, tracking the worst exit status across all of them
# rather than bailing on the first failure, so a single bad env doesn't hide problems in the rest.
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
