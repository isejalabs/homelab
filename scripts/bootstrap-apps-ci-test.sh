#!/bin/sh
# Validates the k8s/bootstrap/helmfile "apps" stage (see k8s/bootstrap/mod.just's `apps` recipe) against a
# throwaway kind cluster, standing in for `just bootstrap::cluster` without touching a real environment.
#
# Usage: scripts/bootstrap-apps-ci-test.sh
# Takes no arguments; run from the repo root (invoked by the bootstrap-apps-ci-test CI workflow). Creates
# and always tears down its own kind cluster, so it's also safe to run locally.
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

set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

CLUSTER_NAME=bootstrap-apps-ci
KUBE_CONTEXT=admin@ci-homelab

# Recorded for log()'s automatic "context" field (see lib/common.sh), matching the kopiur scripts' pattern
# (#1305) -- every kubectl call below targets this same fixed context, so it's worth showing on every log
# line here too, not just the kopiur scripts' env-driven one.
LOG_CTX="${KUBE_CONTEXT}"

# Dumps pod status/describe/logs for anything not Running/Completed on failure, then always tears down the
# kind cluster (registered via `trap ... EXIT` below, so this runs whether the script succeeded or failed).
# Each kubectl dump is captured and re-emitted via log_debug_output rather than left as raw echo/kubectl
# output, so it's one debug-level log line per line of output instead of unstructured terminal noise.
cleanup() {
    exit_code=$?
    if [ "$exit_code" -ne 0 ]; then
        log error "bootstrap-apps-ci-test failed" "exit_code" "$exit_code"
        out=$(kubectl --context "$KUBE_CONTEXT" get pods -A -o wide 2>&1) || true
        log_debug_output "$out"
        kubectl --context "$KUBE_CONTEXT" get pods -A --no-headers 2>/dev/null \
            | awk '$4 != "Running" && $4 != "Completed" { print $1, $2 }' \
            | while read -r ns pod; do
                log info "describing failed pod" "namespace" "$ns" "pod" "$pod"
                out=$(kubectl --context "$KUBE_CONTEXT" describe pod -n "$ns" "$pod" 2>&1) || true
                log_debug_output "$out"
                out=$(kubectl --context "$KUBE_CONTEXT" logs -n "$ns" "$pod" --all-containers --tail=200 2>&1) || true
                log_debug_output "$out"
            done
    fi
    kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# CNI is left uninstalled here since the apps stage only cares about the helm releases below, not networking;
# Cilium itself is one of those releases in a real bootstrap, but it's not needed for this validation.
kind create cluster --name "$CLUSTER_NAME" --config - <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
EOF

# kind names its context "kind-<cluster>" by default; renamed to match KUBE_CONTEXT so the diagnostics/
# cleanup logic above and the helmfile/kubectl calls below all address the same, real-looking context.
kubectl config rename-context "kind-$CLUSTER_NAME" "$KUBE_CONTEXT"

# CRDs stage - same command as k8s/bootstrap/mod.just's `core` recipe.
helmfile -f k8s/bootstrap/helmfile/crds -e ci template -q \
    | yq ea -r -e 'select(.kind == "CustomResourceDefinition")' \
    | kubectl --context "$KUBE_CONTEXT" apply --server-side --force-conflicts -f -

# Apps stage - only the releases labeled ci=true (see apps/helmfile.yaml.gotmpl).
helmfile -f k8s/bootstrap/helmfile/apps -e ci -l ci=true sync --hide-notes
