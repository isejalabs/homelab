#!/bin/sh
# Runs `terragrunt init -backend=false` + `terragrunt validate` against every terragrunt unit under
# terragrunt/, to catch a syntax/type error before it's hit for real by a live `terragrunt plan`/`apply`.
#
# prod and qa units additionally have to have a committed provider lock file (terragrunt/README.md, "Provider lock
# files"): a missing one fails the check, and these units are init'd with `-lockfile=readonly`, so a lock that is
# incomplete (a provider or the hashes for the CI platform missing) fails instead of being silently extended -- which is
# how a lock file used to end up uncommitted: it was created by the manual apply after the merge, in the applying checkout.
#
# Usage: scripts/terragrunt-validate-all.sh [unit-dir ...]
# Without arguments every unit under terragrunt/ is checked; with arguments only the given unit directories (for example
# terragrunt/prod/eu-central-1/prod/checkmk-password). Run from the repo root (invoked by the terragrunt-validate CI workflow).

set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

# `terragrunt validate` alone always configures the real S3 backend first (and fails without cloud
# creds/state access), so each unit is init'd with `-backend=false` before validating - this checks
# syntax/types only, the same scope `plan`/`apply` are deliberately excluded from CI for.
list=$(mktemp)
trap 'rm -f "$list"' EXIT
if [ $# -gt 0 ]; then
    for unit in "$@"; do
        printf '%s/terragrunt.hcl\n' "${unit%/}"
    done > "$list"
else
    find terragrunt -name terragrunt.hcl -not -path '*/.terragrunt-cache/*' > "$list"
fi

status=0

# Succeeds for the units whose provider versions must be pinned by a committed lock file: everything in the prod
# environment and in the qa environment (the other non-prod environments ignore lock files, see .gitignore).
needs_lock() {
    case "$1" in
        terragrunt/prod/*/prod/* | terragrunt/non-prod/*/qa/*) return 0 ;;
    esac
    return 1
}

# Inits and validates every unit, tracking the worst exit status across all of them rather than bailing on
# the first failure, so one bad unit doesn't hide problems in the rest.
while IFS= read -r cfg; do
    dir=$(dirname "$cfg")

    # `src` is docs/architecture/environments.md's dedicated environment for developing a Terraform module
    # itself: its units point `source` at an uncommitted local checkout of that module (sibling to this
    # repo on disk), which by design never exists in a fresh clone - nothing to validate here in CI.
    case "$dir" in terragrunt/*/*/src/*) continue ;; esac

    set -- -backend=false -input=false
    if needs_lock "$dir"; then
        if ! git ls-files --error-unmatch -- "$dir/.terraform.lock.hcl" > /dev/null 2>&1; then
            log error "prod/qa unit has no committed provider lock file (see terragrunt/README.md, Provider lock files)" "unit" "$dir"
            status=1
            continue
        fi
        set -- "$@" -lockfile=readonly
    fi

    if ! out=$(terragrunt run --non-interactive --working-dir "$dir" -- init "$@" 2>&1); then
        log_debug_output "$out"
        log error "terragrunt init failed (for a prod/qa unit also if its committed lock file is incomplete)" "unit" "$dir"
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
