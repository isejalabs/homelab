#!/bin/sh
# Unit test of the hostname helpers in lib/readme-access.sh that check-unit-readme-hostnames.sh relies on: the
# host-to-environment mapping (including the prod exception auth.iseja.net) and the extraction of link hosts from an
# "Access" section. Needs no renderer. Fails with a non-zero status on the first wrong answer.
#
# Usage: scripts/test-readme-access.sh
# Invoked by the docs-link-check CI workflow.

set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(dirname -- "${SCRIPTS_DIR}")
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

. "${SCRIPTS_DIR}/lib/flux-sets.sh"
. "${SCRIPTS_DIR}/lib/readme-access.sh"

failed=0

# Compares $2 (got) with $1 (want) for the case named $3 and counts a failure.
expect() {
    if [ "$1" != "$2" ]; then
        printf 'FAIL %s: want "%s", got "%s"\n' "$3" "$1" "$2" >&2
        failed=1
    fi
}

# Host to environment: want, host.
expect dev "$(readme_host_env dev-whoami.dev.iseja.net)" "prefixed non-prod host"
expect rebuild "$(readme_host_env rebuild-cmk-k8s-cluster-collector.rebuild.iseja.net)" "prefixed host with dashes in the subdomain"
expect prod "$(readme_host_env whoami.prod.iseja.net)" "prod without prefix"
expect prod "$(readme_host_env auth.iseja.net)" "prod exception auth.iseja.net"
expect prod "$(readme_host_env prod-whoami.prod.iseja.net)" "prod label is not validated here (the render rejects a name the overlay does not serve)"
expect "" "$(readme_host_env whoami.dev.iseja.net)" "non-prod host without its prefix"
expect "" "$(readme_host_env qa-whoami.dev.iseja.net)" "prefix of another environment"
expect "" "$(readme_host_env dev-whoami.dev.example.com)" "foreign domain"
expect "" "$(readme_host_env dev-whoami.nope.iseja.net)" "unknown environment"
expect "" "$(readme_host_env a.b.dev.iseja.net)" "more than one label before the environment"
expect "" "$(readme_host_env iseja.net)" "bare domain"

# Link hosts: only link targets in the Access section, outside fenced code, without port, path or placeholders.
cat >"${WORK}/README.md" <<'MD'
# X

## Purpose

[https://purpose.prod.iseja.net](https://purpose.prod.iseja.net)

## Access

| env | URL |
| --- | --- |
| `dev` | [https://dev-a.dev.iseja.net](https://dev-a.dev.iseja.net) |
| `qa` | [https://qa-a.qa.iseja.net:8443/admin?x=1#y](https://qa-a.qa.iseja.net:8443/admin?x=1#y) and `https://code-span.prod.iseja.net` |
| `x` | [https://<env>-a.<env>.iseja.net](https://<env>-a.<env>.iseja.net) |

```sh
curl [https://fenced.prod.iseja.net](https://fenced.prod.iseja.net)
```

## Updates

[https://updates.prod.iseja.net](https://updates.prod.iseja.net)
MD
expect "dev-a.dev.iseja.net qa-a.qa.iseja.net" "$(readme_access_hosts "${WORK}/README.md" | paste -sd ' ' -)" "link hosts of the Access section"

if [ "${failed}" -eq 0 ]; then
    echo "info: readme-access helpers behave as expected" >&2
fi
exit ${failed}
