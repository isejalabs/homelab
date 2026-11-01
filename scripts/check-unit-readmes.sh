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
# Usage: scripts/check-unit-readmes.sh [repo-root]
# repo-root defaults to this script's repo; pass another directory to check a copy of the tree. Invoked by the
# docs-link-check CI workflow.

set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

ROOT="${1:-$(dirname -- "${SCRIPTS_DIR}")}"
NAV="${ROOT}/.ci/mkdocs/mkdocs.yml"
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

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

if [ ! -f "${NAV}" ]; then
    log fatal "docs navigation file not found" "file" ".ci/mkdocs/mkdocs.yml"
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
