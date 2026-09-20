# shellcheck shell=sh
# Shared helpers for scripts/'s own scripts: gum-backed logging, environment validation, kubecontext
# construction, and unrecognized-flag handling. Sourced, not executed directly, and POSIX `sh` only (both
# `sh` and `bash` callers source it) -- see #1275.
#
# Usage (from a script living directly under scripts/):
#   SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
#   . "${SCRIPTS_DIR}/lib/common.sh"
# Assumes the caller has already set SCRIPTS_DIR as above before sourcing this file, and that the caller
# defines its own usage() function (unknown_flag below calls it, but each script's synopsis differs).

REPO_ROOT=$(CDPATH= cd -- "${SCRIPTS_DIR}/.." && pwd)

# Logs one line via gum, calling it directly rather than through the `just log` recipe: `just`'s own
# template substitution mangles embedded double-quote characters in dynamic message content, and going
# through `just` at all pulls it in as a runtime dependency for scripts that, by design, don't otherwise
# need it (#1275's parent scope explicitly leaves converting them into just recipes for later). `.justfile`'s
# own `log`/`logstep` recipes are the equivalent for use *within* actual just recipes (k8s/bootstrap/mod.just)
# and intentionally keep their own copy of this same gum invocation rather than sourcing this file.
log() {
    lvl="$1"
    msg="$2"
    shift 2
    gum log -t rfc3339 -s -l "$lvl" -- "$msg" "$@"
}

# The repo's environment identifiers (see docs/architecture/environments.md), derived from
# k8s/components/envs/'s own directory listing (minus base/, which isn't a real environment) rather than
# hardcoded here a second time, so this stays in sync automatically if an environment is ever added/removed.
list_environments() {
    find "${REPO_ROOT}/k8s/components/envs" -mindepth 1 -maxdepth 1 -type d ! -name base -exec basename {} \; | sort
}

# Exits fatal (via `log`) unless $1 is one of list_environments' entries.
validate_environment() {
    env="$1"
    case " $(list_environments | tr '\n' ' ') " in
        *" ${env} "*) ;;
        *)
            log fatal "-e/--environment must be one of: $(list_environments | paste -sd ' ' -)" "got" "${env}"
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
    log error "unknown flag" "flag" "$1"
    usage
}

# Emits each line of $1 (typically a captured subprocess's combined stdout/stderr) as its own `debug`-level
# log() call: gum log collapses embedded newlines within a single message into one unreadable run-on line,
# so a multi-line blob is split into one call per line to sidestep that rather than logged as one message.
log_debug_output() {
    printf '%s\n' "$1" | while IFS= read -r line; do
        log debug "$line"
    done
}
