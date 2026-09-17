#!/bin/sh
# Upgrades the Kubernetes version on an already-provisioned Talos cluster in place, via `talosctl
# upgrade-k8s` - the in-place counterpart to bumping K8S_VERSION at cluster-creation time. K8S_VERSION below
# is also read directly (via grep) by kustomize-build-all.sh, as the single source of truth for the
# cluster's target k8s version, so a version bump here is picked up by both.
#
# Usage: scripts/upgrade-k8s.sh [--dry-run]
# Run from anywhere inside the repo; the talosconfig is located automatically via `find`. --dry-run is
# passed straight through to `talosctl upgrade-k8s` to preview the upgrade plan without applying it.

TALCONFIG=$(find . -iname talos-config.yaml)
K8S_VERSION="1.34.11" # renovate: github-releases=kubernetes/kubernetes

# Talks to whichever node the talosconfig's first context lists first as an endpoint - any control-plane
# node works, since the upgrade orchestrates the whole cluster from there.
talosctl upgrade-k8s $1 --talosconfig ${TALCONFIG} --nodes $( yq -r '.contexts.*.endpoints.[0]' ${TALCONFIG}) --to ${K8S_VERSION}
