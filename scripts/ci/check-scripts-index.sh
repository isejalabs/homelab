#!/bin/sh
# Checks that the README indexes of scripts/ stay complete: every file under scripts/ (except README.md files)
# must be linked from the nearest README.md above it (walking up to scripts/README.md), as a markdown link
# whose target is the file's path relative to that README, e.g. "[`ci/check-sorting.py`](ci/check-sorting.py)"
# or "[`lib/common.sh`](lib/common.sh)". A README must also not repeat a "##" heading, which is how a section
# ends up documented twice. See .agents/instructions/shell-scripts.md for the convention this enforces.
#
# Usage: scripts/ci/check-scripts-index.sh [repo-root]
# repo-root defaults to this script's repo; pass another directory to check a copy of the tree. Invoked by the
# docs-link-check CI workflow.

set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

ROOT="${1:-$(dirname -- "${SCRIPTS_DIR}")}"
ROOT="${ROOT%/}"
TREE="${ROOT}/scripts"
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

# Prints "level: message key=value ..." to stderr from (level, message, key, value, key, value, ...). Plain
# printf instead of lib/common.sh's gum-backed log(), so the check needs only a POSIX shell and find in CI.
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

# Prints the path of the README.md that indexes the given file: the first one found walking up from the
# file's folder to scripts/. Returns 1 if there is none, not even scripts/README.md.
nearest_readme() {
    d=$(dirname -- "$1")
    while :; do
        if [ -f "${d}/README.md" ]; then
            printf '%s\n' "${d}/README.md"
            return 0
        fi
        [ "${d}" = "${TREE}" ] && return 1
        d=$(dirname -- "${d}")
    done
}

# Prints each "##" heading that occurs more than once in the given README, ignoring fenced code blocks.
duplicate_headings() {
    awk '
        /^```/ { fenced = !fenced; next }
        !fenced && /^## / { if (seen[$0]++) print }
    ' "$1"
}

if [ ! -d "${TREE}" ]; then
    log fatal "no scripts/ folder under the repo root" "root" "${ROOT}"
    exit 1
fi

status=0

# Compiled Python caches are not scripts; everything else counts, also files that are not executable.
find "${TREE}" -type f ! -name README.md ! -name '*.pyc' ! -path '*/__pycache__/*' | sort >"${WORK}/files"
if [ ! -s "${WORK}/files" ]; then
    log fatal "found no files under scripts/ - did the layout change?" "tree" "${TREE}"
    exit 1
fi

while IFS= read -r file; do
    if ! readme=$(nearest_readme "${file}"); then
        log error "no README.md above this file to index it" "file" "${file#"${ROOT}"/}"
        status=1
        continue
    fi
    rel="${file#"$(dirname -- "${readme}")"/}"
    if ! grep -qF "](${rel})" "${readme}"; then
        log error "file is not linked from its README" "file" "${file#"${ROOT}"/}" "readme" "${readme#"${ROOT}"/}"
        status=1
    fi
done <"${WORK}/files"

find "${TREE}" -type f -name README.md | sort >"${WORK}/readmes"
while IFS= read -r readme; do
    duplicate_headings "${readme}" >"${WORK}/dups"
    if [ -s "${WORK}/dups" ]; then
        while IFS= read -r heading; do
            log error "README repeats a heading" "readme" "${readme#"${ROOT}"/}" "heading" "${heading}"
        done <"${WORK}/dups"
        status=1
    fi
done <"${WORK}/readmes"

if [ "${status}" -eq 0 ]; then
    log info "every file under scripts/ is linked from its README" "files" "$(wc -l <"${WORK}/files" | tr -d ' ')"
fi
exit "${status}"
