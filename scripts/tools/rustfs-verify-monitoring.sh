#!/bin/sh
# Verifies one environment's RustFS monitoring identity (the `<env>-checkmk-monitoring` user created by the
# rustfs-bucket-reader Terragrunt unit) end to end: it must be able to read quota/usage of its own buckets, and
# nothing else. Every check is non-mutating: object actions use a random non-existent key, so even a wrongly
# allowed action changes nothing (it would answer 404/204 instead of the expected 403).
#
# Checks (expected HTTP status):
#   200  GET    /rustfs/admin/v3/quota-stats/<own bucket>      for each of the environment's own buckets
#   403  GET    /rustfs/admin/v3/quota-stats/<foreign bucket>  another environment's bucket
#   403  GET    /<own bucket>?list-type=2                       object listing
#   403  GET    /<own bucket>/<random key>                      GetObject (a 404 would mean the action is allowed)
#   403  DELETE /<own bucket>/<random key>                      DeleteObject (a 204 would mean the action is allowed)
#   403  GET    /rustfs/admin/v3/info                           admin:ServerInfo
#   403  GET    /rustfs/admin/v3/scanner/status                 admin:ServerInfo
#
# The endpoint comes from `rustfs.endpoint` in terragrunt/global-secrets.sops.yaml (a "host:port"; https is
# assumed) unless --endpoint is given. The identity's credentials come from its 1Password item
# `checkmk-monitoring#<env>` in the K8S vault, read via `op item get`: `op read` and `op://` references cannot
# address these items, since the secret reference syntax rejects the `#` in the item name. The credentials are
# handed to curl on stdin only, so they never show up in the process list.
#
# Manual only (needs 1Password and network access to the RustFS), not for CI. Exits non-zero if any check
# deviates, printing the response body of each deviation. See terragrunt/README.md ("RustFS monitoring identity").
#
# Usage: scripts/rustfs-verify-monitoring.sh -e <env> [--endpoint <url>]
set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

# SigV4 parameters for curl --aws-sigv4: provider:partition:region:service. RustFS signs like S3 and does not
# care about the region, so the usual default is used.
SIGV4="aws:amz:us-east-1:s3"
OP_VAULT="K8S"

usage() {
    echo "Usage: $(basename "$0") -e <env> [--endpoint <url>]" >&2
    exit 1
}

# Exits fatal (via `log`) unless every tool the script shells out to is present, and curl is new enough to
# know --aws-sigv4 (curl 7.75+).
require_tools() {
    for tool in curl op sops yq gum; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            log fatal "required tool not found" "tool" "${tool}"
            exit 1
        fi
    done
    if ! curl --help all 2>/dev/null | grep -q -- '--aws-sigv4'; then
        log fatal "curl does not support --aws-sigv4 (needs 7.75 or newer)"
        exit 1
    fi
}

# Sets ENDPOINT: the one given via --endpoint, else `https://` plus rustfs.endpoint from the SOPS-encrypted
# global secrets. Either way trailing slashes are stripped, since a trailing slash turns every request into
# `//<path>` and RustFS answers that with a misleading InvalidBucketName.
load_endpoint() {
    if [ -z "${ENDPOINT}" ]; then
        secrets_file="${REPO_ROOT}/terragrunt/global-secrets.sops.yaml"
        secrets_yaml=$(sops -d "${secrets_file}") || {
            log fatal "failed to decrypt secrets file via sops" "file" "${secrets_file}"
            exit 1
        }
        ENDPOINT=$(printf '%s\n' "${secrets_yaml}" | yq -r '.rustfs.endpoint // ""')
        if [ -z "${ENDPOINT}" ]; then
            log fatal "terragrunt/global-secrets.sops.yaml is missing rustfs.endpoint"
            exit 1
        fi
    fi
    case "${ENDPOINT}" in
        http://* | https://*) ;;
        *) ENDPOINT="https://${ENDPOINT}" ;;
    esac
    while [ "${ENDPOINT%/}" != "${ENDPOINT}" ]; do
        ENDPOINT="${ENDPOINT%/}"
    done
}

# Prints one field of the environment's 1Password item (label $1) via `op item get`, concealed fields included.
# Exits fatal if the item or field cannot be read, e.g. because the unit was never applied for this environment.
read_field() {
    value=$(op item get "checkmk-monitoring#${ENV}" --vault "${OP_VAULT}" --fields "label=$1" --reveal) || {
        log fatal "could not read 1Password item field (not applied yet, or not signed in to op?)" \
            "item" "checkmk-monitoring#${ENV}" "field" "$1"
        exit 1
    }
    if [ -z "${value}" ]; then
        log fatal "1Password item field is empty" "item" "checkmk-monitoring#${ENV}" "field" "$1"
        exit 1
    fi
    printf '%s' "${value}"
}

# Prints the environment's own buckets, one per line: always the kopiur backup bucket, plus the Longhorn backup
# bucket for the environments that have a Longhorn S3 backup target. Mirrors `longhorn_envs` in
# terragrunt/_envcommon/rustfs-bucket-reader.hcl -- keep the two in sync.
own_buckets() {
    printf '%s-kopiur-backup\n' "${ENV}"
    case "${ENV}" in
        dev | prod | qa | rebuild) printf '%s-longhorn-backup\n' "${ENV}" ;;
    esac
}

# Prints a bucket that belongs to a different environment, for the cross-environment isolation check.
foreign_bucket() {
    if [ "${ENV}" = "prod" ]; then
        printf 'dev-kopiur-backup'
    else
        printf 'prod-kopiur-backup'
    fi
}

# Sends one SigV4-signed request ($1 method, $2 path with leading slash) as the monitoring identity. Sets STATUS
# to the HTTP status (000 if curl itself failed) and BODY to the response body. The credentials go to curl via a
# config on stdin, not on the command line.
request() {
    body_file=$(mktemp)
    STATUS=$(printf 'user = "%s:%s"\n' "${ACCESS_KEY}" "${SECRET_KEY}" |
        curl -sS -K - --aws-sigv4 "${SIGV4}" -X "$1" -o "${body_file}" -w '%{http_code}' \
            "${ENDPOINT}$2" 2>/dev/null) || STATUS="000"
    BODY=$(head -c 300 "${body_file}")
    rm -f "${body_file}"
}

# Runs one check: $1 label, $2 method, $3 path, $4 expected HTTP status, optional $5 an extended regular
# expression the response body must match (whitespace-tolerant JSON matching is up to the caller's pattern).
# Prints PASS/FAIL (with the reason and the response body on a failure) and counts failures in FAILED.
check() {
    label="$1"
    request "$2" "$3"
    reason=""
    if [ "${STATUS}" != "$4" ]; then
        reason="got ${STATUS}, expected $4"
        [ "${STATUS}" = "000" ] && reason="${reason} (curl failed: endpoint unreachable or TLS error)"
    elif [ -n "${5:-}" ] && ! printf '%s' "${BODY}" | grep -Eq -- "$5"; then
        reason="status ${STATUS} as expected, but the body does not match $5"
    fi
    if [ -z "${reason}" ]; then
        printf 'PASS  %-62s %s\n' "${label}" "${STATUS}"
    else
        printf 'FAIL  %-62s %s\n' "${label}" "${reason}"
        printf '      %s\n' "${BODY}"
        FAILED=$((FAILED + 1))
    fi
}

ENV=""
ENDPOINT=""
while [ $# -gt 0 ]; do
    case "$1" in
        -e | --environment)
            ENV="$2"
            shift 2
            ;;
        --endpoint)
            ENDPOINT="$2"
            shift 2
            ;;
        -h | --help) usage ;;
        -*) unknown_flag "$1" ;;
        *) usage ;;
    esac
done

[ -z "${ENV}" ] && usage
validate_environment "${ENV}"
require_tools
load_endpoint

ACCESS_KEY=$(read_field ACCESS_KEY)
SECRET_KEY=$(read_field SECRET_KEY)

log info "verifying RustFS monitoring identity" "env" "${ENV}" "endpoint" "${ENDPOINT}"

FAILED=0
FOREIGN=$(foreign_bucket)
BUCKETS=$(own_buckets)
OWN=$(printf '%s\n' "${BUCKETS}" | head -n 1)
RANDOM_KEY="verify-$(date +%s)-$$"

for bucket in ${BUCKETS}; do
    check "quota-stats on own bucket ${bucket}" GET "/rustfs/admin/v3/quota-stats/${bucket}" 200 "\"bucket\"[[:space:]]*:[[:space:]]*\"${bucket}\""
done
check "quota-stats on foreign bucket ${FOREIGN}" GET "/rustfs/admin/v3/quota-stats/${FOREIGN}" 403
check "list objects in ${OWN}" GET "/${OWN}?list-type=2" 403
check "GetObject (random key) in ${OWN}" GET "/${OWN}/${RANDOM_KEY}" 403
check "DeleteObject (random key) in ${OWN}" DELETE "/${OWN}/${RANDOM_KEY}" 403
check "admin info" GET "/rustfs/admin/v3/info" 403
check "admin scanner status" GET "/rustfs/admin/v3/scanner/status" 403

if [ "${FAILED}" -gt 0 ]; then
    log error "identity does not behave as expected" "env" "${ENV}" "failed" "${FAILED}"
    exit 1
fi
log info "identity verified: reads quota of its own buckets and nothing else" "env" "${ENV}"
