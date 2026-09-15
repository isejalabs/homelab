#!/bin/sh

set -eu

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

status=0

envs=$(yq -r '.environments | keys | .[]' k8s/bootstrap/helmfile/base/environments.yaml)

for target in crds apps; do
    for env in $envs; do
        if ! out=$(helmfile -f "k8s/bootstrap/helmfile/$target" -e "$env" template -q 2>&1); then
            printf "${RED}helmfile template failed: %s/%s${NC}\n" "$target" "$env"
            echo "$out"
            status=1
            continue
        fi

        printf "${GREEN}OK: %s/%s${NC}\n" "$target" "$env"
    done
done

exit $status
