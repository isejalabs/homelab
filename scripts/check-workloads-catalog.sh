#!/bin/sh
# Checks that the catalog tables in docs/architecture/workloads.md agree with the repo: every table row's
# unit exists with a flux/ folder, every unit under k8s/apps and k8s/infra that has a flux/ folder has a row,
# and each row's "Flux set" column names the set that lists the unit in k8s/bootstrap/cluster/flux/sets/
# (minimal, optional, soaking, or "none" if no set lists it). Only the first word of the Flux set cell counts,
# so the explanatory text after it stays free-form.
#
# Usage: scripts/check-workloads-catalog.sh [repo-root]
# repo-root defaults to this script's repo; pass another directory to check a copy of the tree. Invoked by the
# docs-link-check CI workflow.

set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

ROOT="${1:-$(dirname -- "${SCRIPTS_DIR}")}"
DOC="${ROOT}/docs/architecture/workloads.md"
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

# repo_units and sets_listing (which Flux set lists which unit) are shared with check-unit-readmes.sh.
. "${SCRIPTS_DIR}/lib/flux-sets.sh"

# Prints "level: message key=value ..." to stderr from (level, message, key, value, key, value, ...). Plain
# printf instead of lib/common.sh's gum-backed log(), so the check needs only a POSIX shell, awk and sed in CI.
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

# Prints "<kind>/<category>/<unit> <set>" for each row of the Apps and Infra tables in the doc. The Apps
# table's rows are under "## Apps", the Infra table's under "## Infra"; the set is the first word of the last
# column, backticks removed. The unit is the first column, "<icon> [`unit`](link)": whatever precedes the "[`" (the
# decorative icon) is ignored; the category is the second column, in backticks.
doc_rows() {
    awk -F'|' '
        /^## Apps/ { kind = "apps"; next }
        /^## Infra/ { kind = "infra"; next }
        /^## / { kind = ""; next }
        /^### / { kind = ""; next }
        kind != "" && $3 ~ /^ `/ {
            unit = $2; cat = $3; set = $(NF - 1)
            gsub(/[ `]/, "", cat)
            sub(/^[^[]*\[`/, "", unit); sub(/`\].*$/, "", unit)
            gsub(/`/, "", set); sub(/^ */, "", set); sub(/[^a-z].*$/, "", set)
            print kind "/" cat "/" unit, set
        }' "${DOC}"
}

sets_listing | sort >"${WORK}/sets"
doc_rows | sort >"${WORK}/doc"
repo_units | sort >"${WORK}/units"

status=0

if [ ! -s "${WORK}/doc" ] || [ ! -s "${WORK}/sets" ] || [ ! -s "${WORK}/units" ]; then
    log fatal "parsed no rows, sets or units - did the doc or the sets layout change?"
    exit 1
fi

# Every row's unit must exist, and appear once.
cut -d' ' -f1 "${WORK}/doc" | sort | uniq -d | while read -r u; do
    log error "unit has more than one row in workloads.md" "unit" "$u"
done
if [ -n "$(cut -d' ' -f1 "${WORK}/doc" | sort | uniq -d)" ]; then status=1; fi

for u in $(cut -d' ' -f1 "${WORK}/doc" | sort -u); do
    if ! grep -qFx "$u" "${WORK}/units"; then
        log error "workloads.md row has no matching k8s unit with a flux/ folder" "unit" "$u"
        status=1
    fi
done

# Every unit with a flux/ folder needs a row, and a row's set must match what the sets list.
for u in $(cat "${WORK}/units"); do
    row_set=$(awk -v u="$u" '$1 == u { print $2 }' "${WORK}/doc")
    if [ -z "${row_set}" ]; then
        log error "k8s unit has no row in workloads.md" "unit" "$u"
        status=1
        continue
    fi
    actual=$(awk -v u="$u" '$1 == u { print $2 }' "${WORK}/sets" | paste -sd ',' -)
    [ -n "${actual}" ] || actual=none
    if [ "${row_set}" != "${actual}" ]; then
        log error "Flux set in workloads.md differs from sets/*/kustomization.yaml" "unit" "$u" "doc" "${row_set}" "sets" "${actual}"
        status=1
    fi
done

# Every unit a set lists must exist as a unit (a dangling set entry is flate-test's job, but a listed unit with
# no row is caught above only if its flux/ folder exists).
for u in $(cut -d' ' -f1 "${WORK}/sets" | sort -u); do
    if ! grep -qFx "$u" "${WORK}/units"; then
        log error "a Flux set lists a unit with no flux/ folder" "unit" "$u"
        status=1
    fi
done

if [ "$status" -eq 0 ]; then
    log info "workloads.md matches the Flux sets and k8s/{apps,infra}" "units" "$(wc -l <"${WORK}/units" | tr -d ' ')"
fi
exit $status
