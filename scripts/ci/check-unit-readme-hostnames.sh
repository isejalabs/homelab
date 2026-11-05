#!/bin/sh
# Checks that every hostname a unit README links in its "Access" section is one the unit's overlay really serves for
# that environment (#2111). For each Markdown link `[...](https://host...)` in the "Access" section of
# k8s/{apps,infra}/*/*/README.md, the environment is derived from the host (see readme_host_env in
# lib/readme-access.sh: `<env>-<sub>.<env>.iseja.net`, `<sub>.prod.iseja.net`, and the prod exception
# `<sub>.iseja.net`), the overlay k8s/<unit>/envs/<env> is rendered, and the host must appear in the rendered output.
# That covers every place a hostname comes from (HTTPRoute hostnames rewritten by replace-domain/prefix-domain, the
# external-dns hostname annotation, Keycloak spec.hostname, a HelmRelease value), so it catches typos, the prod
# exceptions and names like `auth`. It does not look the other way: a hostname the overlay serves but the README does
# not link is fine, and plain-text endpoints (LB addresses, host:port without a link) are not read.
#
# Each (unit, environment) overlay is rendered once. Needs `kubectl` (`kubectl kustomize`, no cluster); set KUSTOMIZE to
# another command to render with (default "kubectl kustomize"), e.g. `kustomize build`.
#
# Usage: scripts/check-unit-readme-hostnames.sh [repo-root]
# repo-root defaults to this script's repo; pass another directory to check a copy of the tree. Invoked by the
# docs-link-check CI workflow.

set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

ROOT="${1:-$(dirname -- "${SCRIPTS_DIR}")}"
KUSTOMIZE="${KUSTOMIZE:-kubectl kustomize}"
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

# repo_units and flux_envs are shared with the other README/catalog checks.
. "${SCRIPTS_DIR}/lib/flux-sets.sh"
. "${SCRIPTS_DIR}/lib/readme-access.sh"

# Prints "level: message key=value ..." to stderr from (level, message, key, value, key, value, ...). Plain
# printf instead of lib/common.sh's gum-backed log(), so the check needs only a POSIX shell, awk, sed and the renderer.
log() {
    lvl="$1"
    msg="$2"
    shift 2
    while [ "$#" -ge 2 ]; do
        msg="${msg} $1=$2"
        shift 2
    done
    printf '%s: %s\n' "$lvl" "$msg" >&2
}

# Renders the overlay of unit $1 for environment $2 once and leaves its hostnames, one per line, in
# ${WORK}/hosts.<unit>.<env> (the unit's slashes replaced by "_"). Prints nothing and returns 1 when the render fails,
# the failure is remembered in ${WORK}/failed.<unit>.<env> so it is reported once per overlay.
render_hosts() {
    key="$(echo "$1" | tr '/' '_').$2"
    [ -f "${WORK}/hosts.${key}" ] && return 0
    [ -f "${WORK}/failed.${key}" ] && return 1
    # shellcheck disable=SC2086 # KUSTOMIZE is a command with arguments
    if ! ${KUSTOMIZE} "${ROOT}/k8s/$1/envs/$2" >"${WORK}/render.${key}" 2>"${WORK}/err.${key}"; then
        log error "kustomize build failed, cannot check the hostnames" "unit" "k8s/$1/envs/$2"
        sed 's/^/    /' "${WORK}/err.${key}" >&2
        : >"${WORK}/failed.${key}"
        return 1
    fi
    # Every run of characters a hostname can contain, so "auth.iseja.net" matches as a whole and not inside a longer name.
    tr -c 'A-Za-z0-9.-' '\n' <"${WORK}/render.${key}" | sort -u >"${WORK}/hosts.${key}"
}

# shellcheck disable=SC2086 # KUSTOMIZE is a command with arguments; only its first word is looked up
if ! command -v ${KUSTOMIZE%% *} >/dev/null 2>&1; then
    log fatal "the renderer is not installed" "command" "${KUSTOMIZE}"
    exit 1
fi

status=0
count=0
for u in $(repo_units | sort); do
    readme="${ROOT}/k8s/${u}/README.md"
    [ -f "${readme}" ] || continue
    readme_access_hosts "${readme}" | sort -u >"${WORK}/readme.hosts"
    while IFS= read -r host; do
        [ -n "${host}" ] || continue
        count=$((count + 1))
        env=$(readme_host_env "${host}")
        if [ -z "${env}" ]; then
            log error "cannot tell the environment from the host (expected <env>-<sub>.<env>.${README_DOMAIN}, <sub>.prod.${README_DOMAIN} or <sub>.${README_DOMAIN})" "file" "k8s/${u}/README.md" "host" "${host}"
            status=1
            continue
        fi
        if [ ! -d "${ROOT}/k8s/${u}/envs/${env}" ]; then
            log error "unit has no overlay for the environment of the host" "file" "k8s/${u}/README.md" "host" "${host}" "overlay" "k8s/${u}/envs/${env}"
            status=1
            continue
        fi
        if ! render_hosts "${u}" "${env}"; then
            status=1
            continue
        fi
        key="$(echo "${u}" | tr '/' '_').${env}"
        if ! grep -qFx "${host}" "${WORK}/hosts.${key}"; then
            log error "the overlay does not serve the host linked in Access" "file" "k8s/${u}/README.md" "host" "${host}" "overlay" "k8s/${u}/envs/${env}"
            status=1
        fi
    done <"${WORK}/readme.hosts"
done

if [ "${count}" -eq 0 ]; then
    log fatal "found no hostname links in any Access section - did the README layout change?"
    exit 1
fi
if [ "${status}" -eq 0 ]; then
    log info "every hostname linked in Access is served by its overlay" "hosts" "${count}"
fi
exit $status
