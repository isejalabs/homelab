# shellcheck shell=sh
# Shared helpers for scripts that need to validate an environment identifier, build the kubecontext for one,
# or report an unrecognized flag -- logic that was previously duplicated across kopiur-create.sh,
# kopiur-list.sh, and kopiur-restore.sh. Sourced, not executed directly, and POSIX `sh` only (both `sh` and
# `bash` callers source it) -- see #1275.
#
# Usage (from a script living directly under scripts/):
#   SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
#   . "${SCRIPTS_DIR}/lib/common.sh"
# Assumes the caller has already set SCRIPTS_DIR as above before sourcing this file, and that the caller
# defines its own usage() function (unknown_flag below calls it, but each script's synopsis differs).

REPO_ROOT=$(CDPATH= cd -- "${SCRIPTS_DIR}/.." && pwd)

# The repo's environment identifiers (see docs/architecture/environments.md), derived from
# k8s/components/envs/'s own directory listing (minus base/, which isn't a real environment) rather than
# hardcoded here a second time, so this stays in sync automatically if an environment is ever added/removed.
list_environments() {
    find "${REPO_ROOT}/k8s/components/envs" -mindepth 1 -maxdepth 1 -type d ! -name base -exec basename {} \; | sort
}

# Exits fatal (via `just log`) unless $1 is one of list_environments' entries. Also rejects an empty $1 (an
# omitted -e/--environment), rather than silently treating it as valid -- an earlier space-joined `case`
# pattern (`*" ${env} "*` against `list_environments | tr '\n' ' '`) accidentally matched an empty env against
# the trailing double space that construction left at the end of the joined string (one space from tr
# converting the list's own trailing newline, one from the pattern's own literal padding), letting a missing
# -e slip through uncaught into whatever called this. Confirmed live, 2026-09-18 (#1287 review). grep -Fx
# against one-environment-per-line output has no equivalent padding/substring pitfall.
validate_environment() {
    env="$1"
    if ! list_environments | grep -qFx "${env}"; then
        just log fatal "-e/--environment must be one of: $(list_environments | paste -sd ' ' -)" "got" "${env}"
        exit 1
    fi
}

# Prints the kubecontext name for an environment, following the convention every Talos-generated kubeconfig
# in this repo uses ("admin@<env>-homelab"). Prints nothing for an empty/unset environment, so callers can
# use this unconditionally and fall back to whatever kubecontext is already current. Always returns 0, even
# then -- otherwise `CTX=$(kubecontext_for_environment "")` becomes a failing simple command under `set -e`,
# silently killing any caller that (like kopiur-restore.sh/kopiur-bypass-restore.sh) doesn't already guard
# every call site with `[ -n "${ENV}" ] &&` the way kopiur-list.sh/kopiur-create.sh do. Confirmed live,
# 2026-09-18 (#1287 review) -- masked at the time by the validate_environment bug above letting an empty env
# reach this function at all in scripts that call validate_environment unconditionally first.
kubecontext_for_environment() {
    [ -n "$1" ] && printf 'admin@%s-homelab' "$1"
    return 0
}

# Shared body for an unrecognized flag's `-*)` case arm: logs it, then defers to the caller's own usage().
unknown_flag() {
    just log error "unknown flag" "flag" "$1"
    usage
}
