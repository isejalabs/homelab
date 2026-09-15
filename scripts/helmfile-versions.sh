#!/bin/sh

# Sourced by CI to pin the Helm/Helmfile versions used to render k8s/bootstrap/helmfile.
# shellcheck disable=SC2034 # consumed by whatever sources this file, not this file itself
HELM_VERSION="v4.3.0" # renovate: github-releases=helm/helm
# shellcheck disable=SC2034
HELMFILE_VERSION="v1.7.4" # renovate: github-releases=helmfile/helmfile
