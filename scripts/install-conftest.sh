#!/bin/sh

set -eu

CONFTEST_VERSION="v0.70.0" # renovate: github-releases=open-policy-agent/conftest
CONFTEST_SHA256="e738506fd808f7dc9794ce8e325f89b14932891a4841fe45f1f24c4a9bb3ed96"

install_dir="${1:-/usr/local/bin}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

version_number="${CONFTEST_VERSION#v}"
curl -fsSL "https://github.com/open-policy-agent/conftest/releases/download/${CONFTEST_VERSION}/conftest_${version_number}_Linux_x86_64.tar.gz" -o "$tmp/conftest.tar.gz"
echo "${CONFTEST_SHA256}  $tmp/conftest.tar.gz" | sha256sum -c -
tar -xzf "$tmp/conftest.tar.gz" -C "$tmp" conftest
mkdir -p "$install_dir"
install -m 0755 "$tmp/conftest" "$install_dir/conftest"
