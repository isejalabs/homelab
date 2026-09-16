#!/bin/sh

set -eu

# Validates the k8s/bootstrap/helmfile "apps" stage (see k8s/bootstrap/mod.just's `apps` recipe) against a
# throwaway kind cluster, standing in for `just bootstrap::cluster` without touching a real environment.
#
# Scope, and why (see #1209):
# - The `core` recipe's namespace-creation step is skipped: it hard-references the real per-environment
#   k8s/infra/k8s/components overlay tree, which has no synthetic "ci" entry (and doesn't need one - Helm's
#   own default createNamespace covers the namespaces these releases need).
# - The `core` recipe's personal-credential injection (`op inject`) is skipped: it needs a live 1Password
#   session, which CI doesn't have.
# - The `core` recipe's CRDs installation step IS run below, unmodified, since it has no such dependency.
# - Of the apps-stage releases, onepassword-connect and flux-instance are excluded via the `ci=true` helmfile
#   label (see apps/helmfile.yaml.gotmpl): onepassword-connect can't reach Ready without the real credentials
#   the skipped op-inject step would have created, and flux-instance's values hardcode this repo's real
#   GitRepository sync target - installing it for real would make flux-operator start reconciling the entire
#   live k8s/infra/k8s/apps tree against this throwaway cluster.

CLUSTER_NAME=bootstrap-apps-ci
KUBE_CONTEXT=admin@ci-homelab

cleanup() {
    exit_code=$?
    if [ "$exit_code" -ne 0 ]; then
        echo "=== Diagnostics (exit $exit_code) ==="
        kubectl --context "$KUBE_CONTEXT" get pods -A -o wide || true
        kubectl --context "$KUBE_CONTEXT" get pods -A --no-headers 2>/dev/null \
            | awk '$4 != "Running" && $4 != "Completed" { print $1, $2 }' \
            | while read -r ns pod; do
                echo "--- describe $ns/$pod ---"
                kubectl --context "$KUBE_CONTEXT" describe pod -n "$ns" "$pod" || true
                echo "--- logs $ns/$pod ---"
                kubectl --context "$KUBE_CONTEXT" logs -n "$ns" "$pod" --all-containers --tail=200 || true
            done
    fi
    kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

kind create cluster --name "$CLUSTER_NAME" --config - <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
EOF

kubectl config rename-context "kind-$CLUSTER_NAME" "$KUBE_CONTEXT"

# CRDs stage - same command as k8s/bootstrap/mod.just's `core` recipe.
helmfile -f k8s/bootstrap/helmfile/crds -e ci template -q \
    | yq ea -r -e 'select(.kind == "CustomResourceDefinition")' \
    | kubectl --context "$KUBE_CONTEXT" apply --server-side --force-conflicts -f -

# Apps stage - only the releases labeled ci=true (see apps/helmfile.yaml.gotmpl).
helmfile -f k8s/bootstrap/helmfile/apps -e ci -l ci=true sync --hide-notes
