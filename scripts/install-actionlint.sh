#!/bin/sh

set -eu

ACTIONLINT_VERSION="1.7.12" # renovate: github-releases=rhysd/actionlint
ACTIONLINT_SHA256="8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"

install_dir="${1:-/usr/local/bin}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" -o "$tmp/actionlint.tar.gz"
echo "${ACTIONLINT_SHA256}  $tmp/actionlint.tar.gz" | sha256sum -c -
tar -xzf "$tmp/actionlint.tar.gz" -C "$tmp" actionlint
mkdir -p "$install_dir"
install -m 0755 "$tmp/actionlint" "$install_dir/actionlint"
