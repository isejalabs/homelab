#!/bin/sh

set -eu

# base/ is environment-agnostic and uses the example.com placeholder domain by convention (see
# CLAUDE.md's "Adding/changing a k8s app or infra component") - only envs/ and flux/ manifests
# are checked for it having leaked past the replace-domain/prefix-domain components.
files=$(find k8s -name "*.yaml" -not -path "*/base/*")

# shellcheck disable=SC2086
conftest test --policy policy $files
