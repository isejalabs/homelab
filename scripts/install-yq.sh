#!/bin/sh

set -eu

YQ_VERSION="v4.53.6" # renovate: github-releases=mikefarah/yq
YQ_SHA256="c5f056448f973ae7d39b5401949648a78f2dc1947d6a8eb65be60d5c504b9385"

install_dir="${1:-/usr/local/bin}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" -o "$tmp/yq"
echo "${YQ_SHA256}  $tmp/yq" | sha256sum -c -
mkdir -p "$install_dir"
install -m 0755 "$tmp/yq" "$install_dir/yq"
