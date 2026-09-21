#!/bin/sh
# Runs `terragrunt init -backend=false` + `terragrunt validate` against every terragrunt unit under
# terragrunt/, to catch a syntax/type error before it's hit for real by a live `terragrunt plan`/`apply`.
#
# Usage: scripts/terragrunt-validate-all.sh
# Takes no arguments; run from the repo root (invoked by the terragrunt-validate CI workflow).

set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

# `terragrunt validate` alone always configures the real S3 backend first (and fails without cloud
# creds/state access), so each unit is init'd with `-backend=false` before validating - this checks
# syntax/types only, the same scope `plan`/`apply` are deliberately excluded from CI for.
list=$(mktemp)
trap 'rm -f "$list"' EXIT
find terragrunt -name terragrunt.hcl -not -path '*/.terragrunt-cache/*' > "$list"

status=0

# Inits and validates every unit, tracking the worst exit status across all of them rather than bailing on
# the first failure, so one bad unit doesn't hide problems in the rest.
while IFS= read -r cfg; do
    dir=$(dirname "$cfg")

    # `src` is docs/architecture/environments.md's dedicated environment for developing a Terraform module
    # itself: its units point `source` at an uncommitted local checkout of that module (sibling to this
    # repo on disk), which by design never exists in a fresh clone - nothing to validate here in CI.
    case "$dir" in terragrunt/*/*/src/*) continue ;; esac

    if ! out=$(terragrunt run --non-interactive --working-dir "$dir" -- init -backend=false -input=false 2>&1); then
        log_debug_output "$out"
        log error "terragrunt init failed" "unit" "$dir"
        status=1
        continue
    fi

    if ! out=$(terragrunt run --non-interactive --working-dir "$dir" -- validate -no-color 2>&1); then
        log_debug_output "$out"
        log error "terragrunt validate failed" "unit" "$dir"
        status=1
        continue
    fi

    log info "OK" "unit" "$dir"
done < "$list"

exit $status
