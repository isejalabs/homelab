#!/bin/bash

set -euo pipefail

KUBECONFORM_VERSION="v0.8.0" # renovate: github-releases=yannh/kubeconform
KUBECONFORM_SHA256="9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883"

install_dir="${1:-/usr/local/bin}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz" -o "$tmp/kubeconform.tar.gz"
echo "${KUBECONFORM_SHA256}  $tmp/kubeconform.tar.gz" | sha256sum -c -
tar -xzf "$tmp/kubeconform.tar.gz" -C "$tmp" kubeconform
install -m 0755 "$tmp/kubeconform" "$install_dir/kubeconform"
