#!/bin/sh
# Renders k8s/bootstrap/helmfile's "crds" and "apps" stages for every environment, to catch a broken
# .gotmpl template or bad values before it's hit for real by `just bootstrap::cluster`.
#
# Usage: scripts/helmfile-template-all.sh
# Takes no arguments; run from the repo root (invoked by the helmfile-template CI workflow).

set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

status=0

# Environments are read from the helmfile environments.yaml itself (not a hardcoded list) so this stays in
# sync automatically if an environment is ever added/removed there.
envs=$(yq -r '.environments | keys | .[]' k8s/bootstrap/helmfile/base/environments.yaml)

# Templates both stages for every environment, tracking the worst exit status across all combinations
# rather than bailing on the first failure, so one bad env/stage doesn't hide problems in the rest.
for target in crds apps; do
    for env in $envs; do
        if ! out=$(helmfile -f "k8s/bootstrap/helmfile/$target" -e "$env" template -q 2>&1); then
            log_debug_output "$out"
            just log error "helmfile template failed" "target" "$target" "env" "$env"
            status=1
            continue
        fi

        just log info "OK" "target" "$target" "env" "$env"
    done
done

exit $status
