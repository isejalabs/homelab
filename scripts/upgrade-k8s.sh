#!/bin/sh

TALCONFIG=$(find . -iname talos-config.yaml)
K8S_VERSION="1.34.11" # renovate: github-releases=kubernetes/kubernetes

# Usage: upgrade-k8s.sh [--dry-run]
talosctl upgrade-k8s $1 --talosconfig ${TALCONFIG} --nodes $( yq -r '.contexts.*.endpoints.[0]' ${TALCONFIG}) --to ${K8S_VERSION}
