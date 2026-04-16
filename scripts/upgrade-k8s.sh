#!/bin/sh

TALCONFIG=$(find . -iname talos-config.yaml)

# Usage: upgrade-k8s.sh [--dry-run]
talosctl upgrade-k8s $1 --talosconfig ${TALCONFIG} --nodes $( yq -r '.contexts.*.endpoints.[0]' ${TALCONFIG}) --to 1.34.7 # renovate: github-releases=kubernetes/kubernetes
