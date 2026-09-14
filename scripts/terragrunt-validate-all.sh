#!/bin/sh

set -eu

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# `terragrunt validate` alone always configures the real S3 backend first (and fails without cloud
# creds/state access), so each unit is init'd with `-backend=false` before validating - this checks
# syntax/types only, the same scope `plan`/`apply` are deliberately excluded from CI for.
list=$(mktemp)
trap 'rm -f "$list"' EXIT
find terragrunt -name terragrunt.hcl -not -path '*/.terragrunt-cache/*' > "$list"

status=0

while IFS= read -r cfg; do
    dir=$(dirname "$cfg")

    if ! out=$(terragrunt run --non-interactive --working-dir "$dir" -- init -backend=false -input=false 2>&1); then
        printf "${RED}terragrunt init failed: %s${NC}\n" "$dir"
        echo "$out"
        status=1
        continue
    fi

    if ! out=$(terragrunt run --non-interactive --working-dir "$dir" -- validate -no-color 2>&1); then
        printf "${RED}terragrunt validate failed: %s${NC}\n" "$dir"
        echo "$out"
        status=1
        continue
    fi

    printf "${GREEN}OK: %s${NC}\n" "$dir"
done < "$list"

exit $status
