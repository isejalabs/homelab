#!/bin/sh
# Upgrades the Kubernetes version on an already-provisioned Talos cluster in place, via `talosctl
# upgrade-k8s` - the in-place counterpart to bumping K8S_VERSION at cluster-creation time. K8S_VERSION below
# is also read directly (via grep) by kustomize-build-all.sh, as the single source of truth for the
# cluster's target k8s version, so a version bump here is picked up by both.
#
# Usage: scripts/upgrade-k8s.sh [--dry-run]
# Run from anywhere inside the repo; the talosconfig is located automatically via `find`. --dry-run is
# passed straight through to `talosctl upgrade-k8s` to preview the upgrade plan without applying it.

set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

TALCONFIG=$(find . -iname talos-config.yaml)
K8S_VERSION="1.34.11" # renovate: github-releases=kubernetes/kubernetes

# A single info/fatal pair around the one command, not per-step decomposition (#1275) - `talosctl
# upgrade-k8s` streams its own multi-stage progress straight to the terminal, so its output is deliberately
# left uncaptured/unwrapped rather than forced through log_debug_output's one-line-per-call debug pattern,
# which would swallow that live progress until the whole command finished.
log info "starting Kubernetes upgrade" "to" "${K8S_VERSION}"
if talosctl upgrade-k8s $1 --talosconfig ${TALCONFIG} --nodes $( yq -r '.contexts.*.endpoints.[0]' ${TALCONFIG}) --to ${K8S_VERSION}; then
    log info "Kubernetes upgrade complete" "version" "${K8S_VERSION}"
else
    log fatal "Kubernetes upgrade failed" "version" "${K8S_VERSION}"
    exit 1
fi
