#!/bin/sh
# Non-destructive regression check that Checkmk agent registration still works on one site: it sends the two
# requests the Agent Controller makes against the site's agent receiver, with a host name that does not exist, so
# nothing is registered, linked or signed. Meant to be run after a change to how users log in to a site (SAML,
# LDAP, a new role), which must not touch the `agent_registration` user (an htpasswd user, authenticated with its
# automation secret through the REST API) or the receiver. See docs/identity/checkmk-sso.md.
#
# What it checks, and what each outcome means:
#   1. A wrong password is refused with 401 (the receiver does authenticate).
#   2. The right credentials with an unknown host name end with 404 `Host ... does not exist`. That answer comes
#      from the REST API call `GET host_config`, made as the registration user, so it proves the receiver
#      reached the site, the user was accepted and may read host configurations. Anything else (401, 403, 5xx)
#      is a regression.
# `pairing` is deliberately not checked: in Checkmk 2.5 it needs the permission `general.agent_pairing`, which
# only the `admin` role has by default, so it answers 403 for `agent_registration` without anything being broken.
# A full registration of a real host is not part of this check, it changes the host (UUID, trust).
#
# Usage: CMK_REGISTRATION_PASSWORD=<secret> scripts/checkmk-agent-registration-check.sh \
#            --server <host> --port <receiver port> --site <site> [--user <name>]
#   --server  host name of the Checkmk server, for example monitoring1.home.iseja.net
#   --port    agent receiver port of the site (`omd config show AGENT_RECEIVER_PORT` as the site user), this is
#             the port agents register on, not 443
#   --site    site name
#   --user    registration user, default `agent_registration`
# The secret is read from the environment only (never a flag, so it is not in the process list), for example from
# the site: `su - <site> -c 'cat var/check_mk/web/agent_registration/automation.secret'`. The receiver certificate
# is signed by the site's own CA, so TLS is not verified (`curl -k`); this checks authentication, not trust.
# Exits 0 when both checks pass and 1 otherwise. Needs `curl` and `gum`.
set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

SERVER=""
PORT=""
SITE=""
REG_USER="agent_registration"

usage() {
    echo "Usage: CMK_REGISTRATION_PASSWORD=<secret> $0 --server <host> --port <receiver port> --site <site> [--user <name>]" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --server) SERVER="${2:-}"; shift 2 ;;
        --port) PORT="${2:-}"; shift 2 ;;
        --site) SITE="${2:-}"; shift 2 ;;
        --user) REG_USER="${2:-}"; shift 2 ;;
        -h | --help) usage ;;
        *) unknown_flag "$1" ;;
    esac
done

if [ -z "${SERVER}" ] || [ -z "${PORT}" ] || [ -z "${SITE}" ]; then
    usage
fi
if [ -z "${CMK_REGISTRATION_PASSWORD:-}" ]; then
    log fatal "CMK_REGISTRATION_PASSWORD is not set"
    exit 1
fi

URL="https://${SERVER}:${PORT}/${SITE}/agent-receiver/register_with_hostname"
UNKNOWN_HOST="regression-test-nonexistent"
BODY_FILE=$(mktemp)
trap 'rm -f "${BODY_FILE}"' EXIT

# A random version-4 UUID in the lower-case form the receiver validates; any value works since nothing is stored.
random_uuid() {
    if [ -r /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    else
        uuidgen | tr 'A-F' 'a-f'
    fi
}

# Sends one registration request for the unknown host with the password $1 and prints the HTTP status; the
# response body is left in BODY_FILE. The credentials go through a curl config on stdin, not the command line,
# so the secret is not visible in the process list; backslash and double quote are escaped for that format.
register_unknown_host() {
    escaped=$(printf '%s' "${REG_USER}:$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf 'user = "%s"\n' "${escaped}" |
        curl -sSk -K - -o "${BODY_FILE}" -w '%{http_code}' \
            -H 'Content-Type: application/json' \
            -d "{\"uuid\":\"$(random_uuid)\",\"host_name\":\"${UNKNOWN_HOST}\"}" \
            "${URL}"
}

FAILED=0

wrong_status=$(register_unknown_host "wrong-$(random_uuid)") || wrong_status="curl-failed"
if [ "${wrong_status}" = "401" ]; then
    log info "wrong password refused" "status" "${wrong_status}"
else
    log error "wrong password was not refused with 401" "status" "${wrong_status}"
    FAILED=1
fi

right_status=$(register_unknown_host "${CMK_REGISTRATION_PASSWORD}") || right_status="curl-failed"
if [ "${right_status}" = "404" ] && grep -q "does not exist" "${BODY_FILE}"; then
    log info "registration user accepted, unknown host reported as missing" "status" "${right_status}"
else
    log error "registration with the right credentials did not end with 404 'does not exist'" "status" "${right_status}" "body" "$(head -c 200 "${BODY_FILE}")"
    FAILED=1
fi

if [ "${FAILED}" -ne 0 ]; then
    log fatal "agent registration check failed" "site" "${SITE}"
    exit 1
fi
log info "agent registration check passed" "site" "${SITE}"
