#!/bin/sh
# Checks that every app/infra unit has a README.md that follows the template in k8s/README.md ("README of an
# app/infra unit"): for each directory under k8s/apps and k8s/infra that has a flux/ folder, the README must start
# with a level-1 title, contain the required level-2 headings in the template's order (extra sections are allowed,
# anywhere), and have the four rows of the "At a glance" table. In the "Access" section a URL must be a Markdown
# link, not a code span, so it can be clicked (a placeholder such as https://<env>-app.example.com stays code).
# Headings and rows inside fenced code blocks do not count, so a "## " comment in a shell snippet cannot satisfy or
# break the check. Content is not judged, only the shape, so a section that does not apply still has to say so in a
# line. Each README must also be listed in the docs site navigation (.ci/mkdocs/mkdocs.yml); an unlisted page is
# built and searchable but missing from the sidebar, and the strict docs build does not complain about it.
#
# Beyond the shape, three rows of "At a glance" are checked against the manifests (the READMEs stay hand-written,
# CI keeps them honest; #2111). The cell grammar is documented next to the template in k8s/README.md:
#   Namespace          the first code span is the `namespace:` of base/kustomization.yaml (a unit without one
#                      starts its cell with "none").
#   Flux Kustomization `<name>`, depends on `<a>`, `<b>` or `<name>`, no `dependsOn`: name and dependsOn names of
#                      the first Kustomization in flux/ks.yaml, the dependsOn names as a set.
#   Runs in            "all N environments" or a list of environment code spans, then "(Flux set `<set>`)" or
#                      "(no Flux set, registered in ...)", then optionally "; free prose". Only the part before the
#                      first ";" is parsed: the environments are those whose flux/envs/<env> reach the unit (through
#                      the sets or directly), the set is the one that lists the unit in sets/.
#
# Usage: scripts/check-unit-readmes.sh [repo-root]
# repo-root defaults to this script's repo; pass another directory to check a copy of the tree. Invoked by the
# docs-link-check CI workflow.

set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

ROOT="${1:-$(dirname -- "${SCRIPTS_DIR}")}"
NAV="${ROOT}/.ci/mkdocs/mkdocs.yml"
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

# repo_units, sets_listing and env_units (which Flux set lists a unit, which environments run it) are shared with
# check-workloads-catalog.sh.
. "${SCRIPTS_DIR}/lib/flux-sets.sh"

# Level-2 headings every unit README must have, in this order. Keep in step with the template in k8s/README.md.
REQUIRED_HEADINGS='At a glance|Purpose|Where it is used|Access|Updates|Operations|Cheat sheet|Upstream'
# Rows of the "At a glance" table every unit README must have (first column).
REQUIRED_ROWS='Namespace|Runs in|Installed via|Flux Kustomization'

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

# Prints one problem per line for the README given as $1, nothing if it has the required shape. Fenced code blocks
# (opened by three or more backticks, closed by at least as many) are skipped. A heading counts only if it is the
# whole line "## <name>", and the required ones must appear in the order of REQUIRED_HEADINGS. In the "Access"
# section every http(s) URL in a code span (without a <placeholder>) is reported.
readme_problems() {
    awk -v req="${REQUIRED_HEADINGS}" -v rows="${REQUIRED_ROWS}" '
        BEGIN { nreq = split(req, R, "|"); nrows = split(rows, W, "|"); fence = 0 }
        {
            line = $0
            if (fence == 0 && match(line, /^`+/) && RLENGTH >= 3) { fence = RLENGTH; next }
            if (fence > 0) {
                if (match(line, /^`+[ \t]*$/) && RLENGTH >= fence) fence = 0
                next
            }
            if (!first_seen && line ~ /[^ \t]/) { first_seen = 1; first = line }
            if (line ~ /^## /) {
                h = substr(line, 4); sub(/[ \t]+$/, "", h)
                if (!(h in at)) at[h] = NR
                sec = h
            }
            if (sec == "Access" && match(line, /`https?:\/\/[^`<>]*`/))
                print "line " NR ": URL in a code span in \"Access\", write it as a Markdown link: " substr(line, RSTART, RLENGTH)
            for (i = 1; i <= nrows; i++) if (index(line, "| " W[i] " |") == 1) hasrow[W[i]] = 1
        }
        END {
            if (first !~ /^# [^ \t]/) print "does not start with a level-1 title (\"# <name>\")"
            prev = ""
            for (i = 1; i <= nreq; i++) {
                if (!(R[i] in at)) { print "missing section \"## " R[i] "\""; continue }
                if (prev != "" && at[R[i]] < at[prev]) print "section \"## " R[i] "\" must come before \"## " prev "\""
                else prev = R[i]
            }
            for (i = 1; i <= nrows; i++) if (!(W[i] in hasrow)) print "\"At a glance\" table has no \"" W[i] "\" row"
        }' "$1"
}

# Prints the content of the "At a glance" table row named $2 in the README $1 (the second column, trimmed), or
# nothing if the row does not exist.
row_cell() {
    awk -v r="$2" '
        index($0, "| " r " |") == 1 {
            c = substr($0, length(r) + 5)
            sub(/^[ \t]+/, "", c); sub(/[ \t]*\|?[ \t]*$/, "", c)
            print c
            exit
        }' "$1"
}

# Prints the text between backticks of each code span in $1, one per line.
code_spans() {
    printf '%s\n' "$1" | grep -oE '`[^`]*`' | tr -d '`'
}

# Prints "<name>" and then each "<dependsOn name>" of the first Kustomization document in the Flux ks.yaml $1, one
# per line, nothing if there is none. Quotes, a YAML anchor (&name) and a trailing comment are stripped.
ks_facts() {
    awk '
        function clean(v) {
            sub(/[ \t]+#.*$/, "", v); sub(/^&[A-Za-z0-9_-]+[ \t]+/, "", v); gsub(/^["\x27]|["\x27]$/, "", v)
            sub(/[ \t]+$/, "", v)
            return v
        }
        function flush() {
            if (kind == "Kustomization" && !done) {
                done = 1
                print name
                for (i = 1; i <= nd; i++) print deps[i]
            }
            kind = ""; name = ""; nd = 0; in_meta = 0; in_deps = 0
        }
        /^---/ { flush(); next }
        /^kind:/ { kind = $2; next }
        /^metadata:/ { in_meta = 1; in_deps = 0; next }
        /^spec:/ { in_meta = 0; next }
        /^[^ #]/ { in_meta = 0; in_deps = 0 }
        in_meta && /^  name:/ { v = $0; sub(/^  name:[ \t]*/, "", v); name = clean(v); next }
        /^  dependsOn:/ { in_deps = 1; next }
        /^  [^ #-]/ { in_deps = 0 }
        in_deps && /^ *- name:/ { v = $0; sub(/^ *- name:[ \t]*/, "", v); deps[++nd] = clean(v) }
        END { flush() }' "$1"
}

# Prints the `namespace:` of the kustomization.yaml $1, nothing if it has none.
kustomization_namespace() {
    awk '/^namespace:/ { v = $0; sub(/^namespace:[ \t]*/, "", v); sub(/[ \t]+#.*$/, "", v); gsub(/["\x27]/, "", v); print v; exit }' "$1"
}

# Prints one problem per line for the unit $1 ("<kind>/<category>/<unit>"): its README rows "Namespace", "Flux
# Kustomization" and "Runs in" against the manifests. A row that is missing is left to readme_problems; a row that
# does not follow the grammar is reported once and its details are not compared. The environments and sets come
# from the files ${WORK}/env_units and ${WORK}/sets (lines "<unit> <env>" and "<unit> <set>").
fact_problems() {
    unit="$1"
    readme="${ROOT}/k8s/${unit}/README.md"

    cell=$(row_cell "${readme}" "Namespace")
    if [ -n "${cell}" ]; then
        want=$(kustomization_namespace "${ROOT}/k8s/${unit}/base/kustomization.yaml")
        if [ -z "${want}" ]; then
            case "${cell}" in
            none*) ;;
            *) echo "\"Namespace\" row: the unit sets no namespace in base/kustomization.yaml, the row must start with \"none\"" ;;
            esac
        else
            got=$(code_spans "${cell}" | head -n 1)
            [ "${got}" = "${want}" ] || echo "\"Namespace\" row: first code span is \"${got}\", base/kustomization.yaml has namespace \"${want}\""
        fi
    fi

    cell=$(row_cell "${readme}" "Flux Kustomization")
    if [ -n "${cell}" ]; then
        ks_facts "${ROOT}/k8s/${unit}/flux/ks.yaml" >"${WORK}/ks"
        want_name=$(sed -n 1p "${WORK}/ks")
        want_deps=$(sed 1d "${WORK}/ks" | sort | paste -sd ',' -)
        if [ -z "${want_name}" ]; then
            echo "flux/ks.yaml has no Kustomization to check the \"Flux Kustomization\" row against"
        elif ! printf '%s\n' "${cell}" | grep -qE '^`[^`]+`, (no `dependsOn`|depends on `[^`]+`(, `[^`]+`)*)$'; then
            echo "\"Flux Kustomization\" row must be \`<name>\`, depends on \`<a>\`, \`<b>\` or \`<name>\`, no \`dependsOn\` (move any prose to another section): ${cell}"
        else
            got_name=$(code_spans "${cell}" | head -n 1)
            case "${cell}" in
            *'no `dependsOn`') got_deps="" ;;
            *) got_deps=$(code_spans "${cell}" | sed 1d | sort | paste -sd ',' -) ;;
            esac
            [ "${got_name}" = "${want_name}" ] || echo "\"Flux Kustomization\" row: name is \"${got_name}\", flux/ks.yaml has \"${want_name}\""
            [ "${got_deps}" = "${want_deps}" ] || echo "\"Flux Kustomization\" row: dependsOn is \"${got_deps}\", flux/ks.yaml has \"${want_deps}\""
        fi
    fi

    cell=$(row_cell "${readme}" "Runs in")
    if [ -n "${cell}" ]; then
        head=$(printf '%s\n' "${cell%%;*}" | sed -E 's/[ \t]+$//')
        want_envs=$(awk -v u="${unit}" '$1 == u { print $2 }' "${WORK}/env_units" | sort | paste -sd ',' -)
        want_set=$(awk -v u="${unit}" '$1 == u { print $2 }' "${WORK}/sets" | sort | paste -sd ',' -)
        if ! printf '%s\n' "${head}" | grep -qE '^(all [0-9]+ environments|`[a-z]+`(, `[a-z]+`)*) \((Flux set `[a-z]+`|no Flux set, registered in .+)\)$'; then
            echo "\"Runs in\" row must be \"all N environments\" or a list of environment code spans, then \"(Flux set \`<set>\`)\" or \"(no Flux set, registered in ...)\", then optionally \"; prose\": ${head}"
        else
            case "${head}" in
            all*)
                got_envs=$(flux_envs | sort | paste -sd ',' -)
                n=$(flux_envs | wc -l | tr -d ' ')
                [ "${head#all }" != "${head}" ] && [ "$(printf '%s\n' "${head}" | sed -E 's/^all ([0-9]+) .*/\1/')" = "${n}" ] ||
                    echo "\"Runs in\" row: says all $(printf '%s\n' "${head}" | sed -E 's/^all ([0-9]+) .*/\1/') environments, there are ${n}"
                ;;
            *)
                got_envs=$(code_spans "${head%% (*}" | sort | paste -sd ',' -)
                ;;
            esac
            [ "${got_envs}" = "${want_envs}" ] || echo "\"Runs in\" row: environments are \"${got_envs}\", flux/envs/* reach the unit in \"${want_envs}\""
            case "${head}" in
            *'(Flux set `'*) got_set=$(printf '%s\n' "${head}" | sed -E 's/.*\(Flux set `([a-z]+)`\)$/\1/') ;;
            *) got_set="" ;;
            esac
            [ "${got_set}" = "${want_set}" ] || echo "\"Runs in\" row: Flux set is \"${got_set:-none}\", sets/ list the unit in \"${want_set:-none}\""
        fi
    fi
}

if [ ! -f "${NAV}" ]; then
    log fatal "docs navigation file not found" "file" ".ci/mkdocs/mkdocs.yml"
    exit 1
fi

sets_listing | sort >"${WORK}/sets"
env_units | sort >"${WORK}/env_units"
if [ ! -s "${WORK}/sets" ] || [ ! -s "${WORK}/env_units" ]; then
    log fatal "parsed no Flux sets or environments - did the sets or flux/envs layout change?"
    exit 1
fi

status=0
count=0
for u in $(repo_units | sort); do
    count=$((count + 1))
    readme="${ROOT}/k8s/${u}/README.md"
    if [ ! -f "${readme}" ]; then
        log error "unit has no README.md (template: k8s/README.md)" "unit" "k8s/${u}"
        status=1
        continue
    fi
    if ! grep -qE "^ *- .*: k8s/${u}/README\.md *\$" "${NAV}"; then
        log error "README is not listed in the docs navigation (.ci/mkdocs/mkdocs.yml, Components and apps)" "file" "k8s/${u}/README.md"
        status=1
    fi
    readme_problems "${readme}" >"${WORK}/problems"
    fact_problems "${u}" >>"${WORK}/problems"
    while IFS= read -r p; do
        log error "$p" "file" "k8s/${u}/README.md"
        status=1
    done <"${WORK}/problems"
done

if [ "${count}" -eq 0 ]; then
    log fatal "found no units under k8s/apps and k8s/infra - did the layout change?"
    exit 1
fi
if [ "$status" -eq 0 ]; then
    log info "every unit README follows the template" "units" "${count}"
fi
exit $status
