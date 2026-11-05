#!/bin/sh
# Runs `kubectl kustomize` + kubeconform against every kustomize overlay under k8s/ (except the
# non-standalone Components under k8s/components/), to catch a broken build or schema-invalid manifest
# before Flux hits it for real. Also checks that every keycloak-realm and keycloak-automation Terragrunt unit's
# `keycloak_url` matches the hostname its environment's Keycloak overlay serves.
#
# Usage: scripts/kustomize-build-all.sh
# Takes no arguments; run from the repo root (invoked by the kustomize-build CI workflow).

set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

# SealedSecret's community schema forbids `spec.template.metadata.creationTimestamp`, which every
# kubeseal-generated manifest sets to null as part of ObjectMeta - a schema-catalog inaccuracy, not
# a real problem with our manifests, so its schema validation is skipped rather than worked around.
SKIP_KINDS='SealedSecret'

# Kubernetes version the manifests are validated against (kubeconform schemas). Keep it at the version the
# clusters run (bumped by Renovate, see the pin in .github/renovate/pin-versions.json5).
K8S_VERSION="1.35.9" # renovate: github-releases=kubernetes/kubernetes

# Prints the public hostname that a rendered Keycloak overlay (read from stdin) declares for its resource of kind $1:
# `Keycloak` (spec.hostname.hostname) or `HTTPRoute` (first entry of spec.hostnames). Prints nothing if there is none.
# Relies on kustomize's stable output: apiVersion/kind first in each document, documents separated by `---`.
rendered_hostname() {
    awk -v kind="$1" '
        /^---$/ { k = "" }
        /^kind: / { k = $2 }
        k == kind && kind == "Keycloak" && /^  hostname:$/ { getline; sub(/^ *hostname: */, ""); print }
        k == kind && kind == "HTTPRoute" && /^  hostnames:$/ { getline; sub(/^ *- */, ""); print }'
}

# Fails (status=1) when the hostname a keycloak-realm or keycloak-automation Terragrunt unit calls (`keycloak_url`) differs from the one its
# environment's Keycloak overlay serves, either on the `Keycloak` resource or on the `HTTPRoute`. The Terragrunt side
# cannot read the overlay's replace-domain/prefix-domain result, so it is the one typed by hand (#1946); a drift
# would otherwise only show up as a failing realm apply or a wrong issuer. Needs no cluster, only `kubectl kustomize`.
check_keycloak_hostnames() {
    for hcl in $(find terragrunt \( -path '*/keycloak-realm/terragrunt.hcl' -o -path '*/keycloak-automation/terragrunt.hcl' \) | sort); do
        env=$(basename "$(dirname "$(dirname "$hcl")")")
        overlay="k8s/apps/identity/keycloak/envs/${env}"
        url_host=$(sed -n 's|^ *keycloak_url *= *"https://\([^"/]*\)/\{0,1\}".*|\1|p' "$hcl")

        if [ -z "$url_host" ]; then
            log error "no https keycloak_url found in the Keycloak Terragrunt unit" "file" "$hcl"
            status=1
            continue
        fi
        if ! manifests=$(kubectl kustomize "$overlay" 2>&1); then
            log_debug_output "$manifests"
            log error "kustomize build failed, cannot check the Keycloak hostname" "unit" "$overlay" "file" "$hcl"
            status=1
            continue
        fi

        keycloak_host=$(echo "$manifests" | rendered_hostname Keycloak)
        route_host=$(echo "$manifests" | rendered_hostname HTTPRoute)
        if [ "$url_host" != "$keycloak_host" ] || [ "$url_host" != "$route_host" ]; then
            log error "Keycloak hostname differs between Terragrunt and the overlay" "file" "$hcl" \
                "keycloak_url" "$url_host" "Keycloak" "${keycloak_host:-none}" "HTTPRoute" "${route_host:-none}"
            status=1
        fi
    done
}

# Listed into a file rather than piped into the while loop below, so the loop runs in the
# current shell (not a subshell) and `status` set inside it is still visible at `exit $status`.
list=$(mktemp)
trap 'rm -f "$list"' EXIT
find k8s -name kustomization.yaml > "$list"

status=0

# A Flux Kustomization's `spec.targetNamespace` would be a second source of truth next to the `namespace:` in
# the unit's base/kustomization.yaml (and Flux's one silently wins), so it's banned in every flux/ks.yaml (see
# AGENTS.md "Adding/changing a k8s app or infra component", #1896). Checked up front, not per overlay below,
# since ks.yaml lives in flux/ rather than in a built overlay.
for ks in $(find k8s -path '*/flux/ks.yaml'); do
    if grep -q '^  targetNamespace:' "$ks"; then
        log error "spec.targetNamespace is not allowed, set namespace: in base/kustomization.yaml instead" "file" "$ks"
        status=1
    fi
done

check_keycloak_hostnames

# Builds and validates every overlay, tracking the worst exit status across all of them rather than bailing
# on the first failure, so one bad overlay doesn't hide problems in the rest.
while IFS= read -r kustomization; do
    dir=$(dirname "$kustomization")

    # k8s/components/* are kustomize Components, meant to be pulled in via `components:` by the
    # overlays under envs/ that this loop already builds - they can't be built standalone.
    case "$dir" in k8s/components/*) continue ;; esac

    if ! manifests=$(kubectl kustomize "$dir" 2>&1); then
        log_debug_output "$manifests"
        log error "kustomize build failed" "unit" "$dir"
        status=1
        continue
    fi

    if ! echo "$manifests" | kubeconform -strict -ignore-missing-schemas -skip "$SKIP_KINDS" \
        -kubernetes-version "$K8S_VERSION" \
        -schema-location default \
        -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
        -summary; then
        log error "kubeconform failed" "unit" "$dir"
        status=1
        continue
    fi

    log info "OK" "unit" "$dir"
done < "$list"

exit $status
