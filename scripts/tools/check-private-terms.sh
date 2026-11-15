#!/bin/sh
# Flags files that contain a term from a private list kept OUTSIDE the repository (ADR 0019: the specific strings
# that must not be published are never committed, so they cannot be checked by a rule in the repo). Run by the
# disclosure-private-terms pre-commit hook on the changed files, or by hand.
#
# The list is a tab-separated file, one entry per line: category<TAB>kind<TAB>term. kind is "literal" (a fixed
# string) or "regex" (an extended regular expression); the term is matched case-insensitively and as a whole word.
# The category is only a label for the owner. Blank lines and lines starting with # (the first row documents the
# format) are ignored, and a line with a single column is read as a literal term. The path comes from
# DISCLOSURE_TERMS_FILE, else from ${XDG_CONFIG_HOME:-$HOME/.config}/homelab/disclosure-terms.tsv. With neither the
# check is a no-op that says so and exits 0 (CI, other contributors). It never prints a term, a regex or the
# matching line, only file:line, so its output is safe to paste. A hit exits 1, an unusable list exits 2.
#
# Usage: scripts/tools/check-private-terms.sh <file>...
#        scripts/tools/check-private-terms.sh --all     # every file tracked by git, from the repo root

set -eu

# Prints the path of the term list to use, or nothing when none is configured.
terms_path() {
    if [ -n "${DISCLOSURE_TERMS_FILE:-}" ]; then
        printf '%s\n' "${DISCLOSURE_TERMS_FILE}"
        return
    fi
    default="${XDG_CONFIG_HOME:-${HOME:-}/.config}/homelab/disclosure-terms.tsv"
    if [ -f "${default}" ]; then
        printf '%s\n' "${default}"
    fi
}

TERMS=$(terms_path)
if [ -z "${TERMS}" ]; then
    echo "disclosure-private-terms: skipped, no private term list configured (set DISCLOSURE_TERMS_FILE, see docs/architecture/ci.md#disclosure-guard)"
    exit 0
fi
if [ ! -r "${TERMS}" ]; then
    echo "disclosure-private-terms: the configured term list is not a readable file (DISCLOSURE_TERMS_FILE or the default path)" >&2
    exit 2
fi

WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

# Split the list into literal terms and regexes. An empty pattern would match every line, so empty terms are dropped.
awk -F'\t' -v lit="${WORK}/literals" -v rx="${WORK}/regexes" '
    /^[ \t]*#/ || /^[ \t]*$/ { next }
    NF == 1 { if ($1 != "") print $1 > lit; next }
    $3 == "" { next }
    tolower($2) == "regex" { print $3 > rx; next }
    { print $3 > lit }
' "${TERMS}"
touch "${WORK}/literals" "${WORK}/regexes"
if [ ! -s "${WORK}/literals" ] && [ ! -s "${WORK}/regexes" ]; then
    echo "disclosure-private-terms: skipped, the term list has no terms"
    exit 0
fi

# A regex that grep cannot compile makes the whole list unusable: say which entry number, never what it is.
n=0
while IFS= read -r re; do
    n=$((n + 1))
    rc=0
    printf '' | grep -E -w -i -e "${re}" > /dev/null 2>&1 || rc=$?
    if [ "${rc}" -ge 2 ]; then
        echo "disclosure-private-terms: regex entry ${n} of the term list is not a valid extended regular expression" >&2
        exit 2
    fi
done < "${WORK}/regexes"

if [ "$#" -eq 0 ]; then
    exit 0
fi
if [ "${1:-}" = "--all" ]; then
    git ls-files -z > "${WORK}/files0"
else
    printf '%s\0' "$@" > "${WORK}/files0"
fi

# -I skips binary files; cut drops the matching line so a term never reaches the output.
: > "${WORK}/hits"
if [ -s "${WORK}/literals" ]; then
    xargs -0 grep -I -n -i -w -F -f "${WORK}/literals" -- < "${WORK}/files0" 2>/dev/null | cut -d: -f1,2 >> "${WORK}/hits" || true
fi
if [ -s "${WORK}/regexes" ]; then
    xargs -0 grep -I -n -i -w -E -f "${WORK}/regexes" -- < "${WORK}/files0" 2>/dev/null | cut -d: -f1,2 >> "${WORK}/hits" || true
fi
if [ -s "${WORK}/hits" ]; then
    sort -u "${WORK}/hits" | sed 's/$/: contains a term from the private list/'
    exit 1
fi
