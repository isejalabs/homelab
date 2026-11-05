#!/bin/sh
# Runs `flate test all` (home-operations/flate) against every environment's top-level Flux sync target, to
# catch a Flux Kustomization pointing at a path/name that doesn't actually exist anywhere in the tree.
#
# Usage: scripts/flate-test-all.sh
# Takes no arguments; run from the repo root (invoked by the flate-test-all CI workflow).

set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

# home-operations/flate/action sets FLATE_BASE (default: the repo's default branch) to enable its
# changed-only mode. This check always validates the full tree per env, not just a PR's diff, so unset it.
unset FLATE_BASE

status=0

# Runs flate against each env's sync target in turn, tracking the worst exit status across all of them
# rather than bailing on the first failure, so a single bad env doesn't hide problems in the rest. flate's own
# output streams straight to the terminal as it runs (not captured), so it isn't wrapped as debug logging
# here the way other scripts' captured subprocess output is - doing so would delay its visibility until the
# whole step finishes instead of showing progress live.
for env in $(list_environments); do
    dir="k8s/bootstrap/cluster/flux/envs/$env"

    if ! flate test all --path "$dir"; then
        log error "flate test failed" "unit" "$dir"
        status=1
        continue
    fi

    log info "OK" "unit" "$dir"
done

exit $status
