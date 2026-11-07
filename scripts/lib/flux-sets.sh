# shellcheck shell=sh
# Shared helpers for the docs-consistency checks (check-workloads-catalog.sh, check-unit-readmes.sh): which units
# exist, which Flux set lists a unit, and which environments end up running a unit. Sourced, not executed directly,
# and POSIX `sh` only. Independent of lib/common.sh on purpose: that file needs gum, and these checks run in CI with
# nothing but a POSIX shell, awk and sed.
#
# The caller sets ROOT (repo root, or a copy of the tree) before calling any function here; SETS is derived from it.

SETS="${ROOT}/k8s/bootstrap/cluster/flux/sets"
FLUX_ENVS="${ROOT}/k8s/bootstrap/cluster/flux/envs"

# Prints "<kind>/<category>/<unit>" for each directory under k8s/apps and k8s/infra that has a flux/ folder.
repo_units() {
    for kind in apps infra; do
        for d in "${ROOT}/k8s/${kind}"/*/*/flux; do
            [ -d "$d" ] || continue
            rel=${d#"${ROOT}/k8s/"}
            echo "${rel%/flux}"
        done
    done
}

# Prints "<kind>/<category>/<unit> <set>" for each unit a sets/<dir>/kustomization.yaml lists, where <set> is
# the name of the directory the listing file is in (apps/minimal -> minimal). A unit listed in more than one
# set gets one line per set, which then shows up as a mismatch in the callers.
sets_listing() {
    for f in "${SETS}"/apps/minimal "${SETS}"/apps/optional "${SETS}"/infra/minimal "${SETS}"/infra/optional "${SETS}"/soaking; do
        set_name=$(basename "$f")
        sed -E -n 's#^ *- *(\.\./)*(apps|infra)/([^/]+)/([^/]+)/flux *$#\2/\3/\4#p' "$f/kustomization.yaml" |
            while read -r unit || [ -n "$unit" ]; do
                echo "$unit $set_name"
            done
    done
}

# Prints the environments, one per line: the directory names under flux/envs.
flux_envs() {
    for d in "${FLUX_ENVS}"/*/; do
        [ -f "${d}kustomization.yaml" ] || continue
        basename "$d"
    done
}

# Prints the entries of the top-level `resources:` list of the kustomization.yaml in directory $1, one per line,
# comments and trailing blanks removed. Components, patches and other keys are not followed.
kustomization_resources() {
    awk '
        /^resources:/ { in_res = 1; next }
        /^[^ #-]/ { in_res = 0 }
        in_res && /^ *- / {
            line = $0
            sub(/^ *- */, "", line); sub(/[ \t]+#.*$/, "", line); sub(/[ \t]+$/, "", line)
            if (line != "") print line
        }' "$1/kustomization.yaml"
}

# Prints "<kind>/<category>/<unit>" for each unit reachable from the kustomization.yaml in directory $1 through
# its `resources:` lists: a `.../k8s/{apps,infra}/<category>/<unit>/flux` entry is a unit, any other directory is
# followed. Needs the real path of ROOT in ROOT_REAL so entries resolve to a comparable form.
reachable_units() {
    for entry in $(kustomization_resources "$1"); do
        resolved=$(CDPATH= cd -- "$1/${entry}" 2>/dev/null && pwd -P) || continue
        case "${resolved}" in
        "${ROOT_REAL}"/k8s/apps/*/*/flux | "${ROOT_REAL}"/k8s/infra/*/*/flux)
            rel=${resolved#"${ROOT_REAL}/k8s/"}
            echo "${rel%/flux}"
            ;;
        *)
            [ -f "${resolved}/kustomization.yaml" ] && reachable_units "${resolved}"
            ;;
        esac
    done
}

# Prints "<kind>/<category>/<unit> <env>" for each unit an environment's flux/envs/<env>/kustomization.yaml
# ends up with, whether directly or through the sets it includes.
env_units() {
    ROOT_REAL=$(CDPATH= cd -- "${ROOT}" && pwd -P)
    for env in $(flux_envs); do
        reachable_units "${FLUX_ENVS}/${env}" | sort -u | while read -r unit; do
            echo "${unit} ${env}"
        done
    done
}
