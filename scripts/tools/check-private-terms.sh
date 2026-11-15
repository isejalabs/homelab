#!/bin/sh
# Flags files that contain a term from a private list kept OUTSIDE the repository (ADR 0019: the specific strings
# that must not be published are never committed, so they cannot be checked by a rule in the repo). Run by the
# disclosure-private-terms pre-commit hook on the changed files, or by hand.
#
# The list is a plain text file, one term per line, matched as a case-insensitive fixed string; blank lines and
# lines starting with # are ignored. Its path comes from DISCLOSURE_TERMS_FILE, else from
# ${XDG_CONFIG_HOME:-$HOME/.config}/homelab/disclosure-terms.txt. With neither the check is a no-op that says so
# and exits 0 (CI, other contributors). It never prints a term or the matching line, only file:line, so its output
# is safe to paste. A hit exits 1.
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
    default="${XDG_CONFIG_HOME:-${HOME:-}/.config}/homelab/disclosure-terms.txt"
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

# One term per line without comments and blank lines: an empty pattern would match every line.
grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "${TERMS}" > "${WORK}/terms" || true
if [ ! -s "${WORK}/terms" ]; then
    echo "disclosure-private-terms: skipped, the term list has no terms"
    exit 0
fi

if [ "$#" -eq 0 ]; then
    exit 0
fi
if [ "${1:-}" = "--all" ]; then
    git ls-files -z > "${WORK}/files0"
else
    printf '%s\0' "$@" > "${WORK}/files0"
fi

# -I skips binary files; cut drops the matching line so a term never reaches the output.
hits=$(xargs -0 grep -I -n -i -F -f "${WORK}/terms" -- < "${WORK}/files0" | cut -d: -f1,2 || true)
if [ -n "${hits}" ]; then
    printf '%s\n' "${hits}" | sed 's/$/: contains a term from the private list/'
    exit 1
fi
