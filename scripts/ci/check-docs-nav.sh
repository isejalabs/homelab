#!/bin/sh
# Checks that the docs site navigation (the `nav:` list in .ci/mkdocs/mkdocs.yml) and the Markdown files agree:
# every Markdown file that the site serves must be listed in `nav`, and every `nav` entry must point at an existing
# file. MkDocs builds an unlisted page and makes it searchable but gives it no sidebar entry, and reports it only at
# INFO level (validation.omitted_files), so a new page is easily forgotten; the sidebar is the only place that makes
# a page discoverable. The docs-build workflow is not a required check, so this runs in the required docs-link-check
# workflow instead. See docs/README.md ("Documentation site") for the nav conventions.
#
# The files that the site does not serve are the ones that `exclude_docs` in mkdocs.yml drops. That rule is not
# evaluated here; the same directories and files are listed in `excluded` below and have to be kept in step with it
# (the docs-build workflow's strict build reports a page that this list lets through but the site does not serve).
#
# Usage: scripts/ci/check-docs-nav.sh [repo-root]
# repo-root defaults to this script's repo; pass another directory to check a copy of the tree. Invoked by the
# docs-link-check CI workflow.

set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

ROOT="${1:-$(dirname -- "${SCRIPTS_DIR}")}"
ROOT="${ROOT%/}"
NAV="${ROOT}/.ci/mkdocs/mkdocs.yml"
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

# Prints every Markdown file of the checkout (as a path relative to the root) that the site serves, one per line.
# Mirrors `exclude_docs` in mkdocs.yml: hidden tooling folders, retired material, Terraform provider caches, agent
# instructions and local tooling notes.
served_markdown() {
    (
        cd "${ROOT}"
        find . \
            \( -path ./.git -o -path ./.github -o -path ./.agents -o -path ./.claude -o -path ./.codex \
            -o -path ./.commons -o -path ./.ci -o -path ./.vscode -o -path ./_attic -o -path ./ZZ.bak \
            -o -name .terraform \) -prune -o \
            -type f -name '*.md' -print |
            sed 's|^\./||' |
            grep -vxE 'AGENTS\.md|CLAUDE\.md|scripts/agent/README\.md'
    )
}

# Prints the target of every entry of the `nav:` list, one per line. A nav entry is `<title>: <path>.md` (the title
# may be quoted and contain colons or dots), so the path is whatever follows the last ": " up to the end of the line.
nav_targets() {
    awk '/^nav:/ { in_nav = 1; next } in_nav && /^[^ -]/ { in_nav = 0 } in_nav' "${NAV}" |
        sed -nE 's/^.*: ([^ ]+\.md) *$/\1/p'
}

if [ ! -f "${NAV}" ]; then
    log fatal "docs navigation file not found" "file" ".ci/mkdocs/mkdocs.yml"
    exit 1
fi

served_markdown | sort >"${WORK}/files"
nav_targets | sort >"${WORK}/nav"
if [ ! -s "${WORK}/files" ] || [ ! -s "${WORK}/nav" ]; then
    log fatal "found no Markdown files or no nav entries - did the layout change?"
    exit 1
fi

status=0

comm -23 "${WORK}/files" "${WORK}/nav" >"${WORK}/unlisted"
while IFS= read -r f; do
    log error "page is not listed in the docs navigation (add it to nav in .ci/mkdocs/mkdocs.yml)" "file" "${f}"
    status=1
done <"${WORK}/unlisted"

comm -13 "${WORK}/files" "${WORK}/nav" >"${WORK}/dangling"
while IFS= read -r f; do
    log error "nav entry points at a file that does not exist or is not served" "file" "${f}"
    status=1
done <"${WORK}/dangling"

dups=$(uniq -d "${WORK}/nav")
for f in ${dups}; do
    log error "file is listed more than once in the docs navigation" "file" "${f}"
    status=1
done

if [ "${status}" -eq 0 ]; then
    log info "every served Markdown file is listed in the docs navigation" "files" "$(wc -l <"${WORK}/files" | tr -d ' ')"
fi
exit "${status}"
