#!/bin/sh

# Sourced by CI to pin the OpenTofu/Terragrunt versions used to validate terragrunt/.
# shellcheck disable=SC2034 # consumed by whatever sources this file, not this file itself
TOFU_VERSION="1.12.6" # renovate: github-releases=opentofu/opentofu
# shellcheck disable=SC2034
TERRAGRUNT_VERSION="0.99.5" # renovate: github-releases=gruntwork-io/terragrunt
