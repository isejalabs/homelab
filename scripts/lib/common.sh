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

# Exits fatal (via `just log`) unless $1 is one of list_environments' entries.
validate_environment() {
    env="$1"
    case " $(list_environments | tr '\n' ' ') " in
        *" ${env} "*) ;;
        *)
            just log fatal "-e/--environment must be one of: $(list_environments | paste -sd ' ' -)" "got" "${env}"
            exit 1
            ;;
    esac
}

# Prints the kubecontext name for an environment, following the convention every Talos-generated kubeconfig
# in this repo uses ("admin@<env>-homelab"). Prints nothing for an empty/unset environment, so callers can
# use this unconditionally and fall back to whatever kubecontext is already current.
kubecontext_for_environment() {
    [ -n "$1" ] && printf 'admin@%s-homelab' "$1"
}

# Shared body for an unrecognized flag's `-*)` case arm: logs it, then defers to the caller's own usage().
unknown_flag() {
    just log error "unknown flag" "flag" "$1"
    usage
}
