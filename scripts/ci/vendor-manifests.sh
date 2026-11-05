#!/bin/sh
# Keeps the upstream manifests vendored next to a kustomize unit (`<unit>/.../vendor/<file>`) identical to the
# upstream file named in that unit's kustomization.yaml. Vendoring exists so that Flux's `kustomize build` never
# fetches a manifest from the internet (an outage then fails the unit even though nothing changed in git).
#
# A vendored file is declared in a kustomization.yaml by a comment holding only the upstream URL, immediately
# followed by the resource entry for the local copy:
#
#   resources:
#     # https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
#     - vendor/standard-install.yaml
#
# Renovate bumps the version inside that URL comment (customManagers in .github/renovate.json5 match it like they
# matched the former remote resource), then `check` fails until `update` has fetched the matching upstream file.
#
# Usage: scripts/vendor-manifests.sh check|update
#   check   fail if a vendored file differs from (or is missing next to) the upstream file its comment names
#   update  (re)download every vendored file from its comment's URL
# Run from the repo root; `check` is invoked by the kustomize-build CI workflow.

set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

usage() {
    echo "Usage: $0 check|update" >&2
    exit 2
}

# Prints "<url><TAB><path>" for every vendored file declared in the kustomization.yaml given as $1, with the path
# relative to the repo root. A declaration is a comment line holding only a URL, directly followed by a
# `- vendor/...` resource entry.
declared_vendored_files() {
    awk -v dir="$(dirname "$1")" '
        /^[[:space:]]*# https:\/\/[^[:space:]]+[[:space:]]*$/ { url = $2; next }
        /^[[:space:]]*- vendor\// && url != "" { print url "\t" dir "/" $2 }
        { url = "" }' "$1"
}

[ $# -eq 1 ] || usage
mode="$1"
case "$mode" in check | update) ;; *) usage ;; esac

list=$(mktemp)
tmp=$(mktemp)
pairs=$(mktemp)
trap 'rm -f "$list" "$tmp" "$pairs"' EXIT
find k8s -name kustomization.yaml | sort > "$list"

status=0
count=0

# Listed into a file rather than piped, so the loops run in the current shell and `status`/`count` survive them.
while IFS= read -r kustomization; do
    declared_vendored_files "$kustomization" > "$pairs"
    while IFS="$(printf '\t')" read -r url path; do
        [ -n "$url" ] || continue
        count=$((count + 1))

        if ! curl -fsSL --retry 3 --retry-delay 2 -o "$tmp" "$url"; then
            log error "download failed" "url" "$url" "file" "$path"
            status=1
            continue
        fi

        if [ "$mode" = update ]; then
            mkdir -p "$(dirname "$path")"
            cp "$tmp" "$path"
            log info "updated" "file" "$path"
        elif cmp -s "$tmp" "$path"; then
            log info "OK" "file" "$path"
        else
            log error "vendored file differs from upstream, run scripts/vendor-manifests.sh update" "file" "$path" "url" "$url"
            status=1
        fi
    done < "$pairs"
done < "$list"

if [ "$count" -eq 0 ]; then
    log error "no vendored files declared in any kustomization.yaml"
    status=1
fi

exit $status
