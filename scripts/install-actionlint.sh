#!/bin/sh
# Downloads and installs a pinned actionlint release (linux/amd64), verifying its checksum before install,
# for the actionlint CI workflow to lint .github/workflows/*.yml.
#
# Usage: scripts/install-actionlint.sh [install_dir]
# install_dir defaults to /usr/local/bin. ACTIONLINT_VERSION/ACTIONLINT_SHA256 below are kept in sync by
# Renovate (see the `# renovate:` comment) - bump the sha alongside the version if Renovate ever fails to.

set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

ACTIONLINT_VERSION="1.7.12" # renovate: github-releases=rhysd/actionlint
ACTIONLINT_SHA256="8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"

install_dir="${1:-/usr/local/bin}"

# Downloaded into a scratch dir (not directly into install_dir) so the checksum can be verified, and the
# archive extracted, before anything touches the real install location.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

log info "installing actionlint" "version" "${ACTIONLINT_VERSION}" "dir" "${install_dir}"
curl -fsSL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" -o "$tmp/actionlint.tar.gz"
echo "${ACTIONLINT_SHA256}  $tmp/actionlint.tar.gz" | sha256sum -c -
tar -xzf "$tmp/actionlint.tar.gz" -C "$tmp" actionlint
mkdir -p "$install_dir"
install -m 0755 "$tmp/actionlint" "$install_dir/actionlint"
log info "actionlint installed" "path" "${install_dir}/actionlint"
