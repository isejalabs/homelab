#!/bin/sh
# Restores the Keycloak database from a `pg_dump` in the environment's `<env>-keycloak-db` bucket, safely
# against a concurrent Flux reconcile and without deleting the running database. See
# docs/keycloak-backup-restore.md for the procedure around this script.
#
# Why a second database in the same cluster, and not a new CloudNativePG `Cluster`: CloudNativePG can only
# bootstrap a cluster from a live PostgreSQL source (`initdb.import` runs `pg_dump` over the network) or from
# base backups plus archived WAL (`recovery`); it cannot read a dump file from a bucket, and this cluster
# deliberately archives no WAL. So the dump is restored into a scratch database `keycloak_restore` next to the
# live `keycloak`, and swapped in by renaming both once everything that writes has been stopped.
#
# Phases:
#   1. Select and verify (non-destructive, Keycloak keeps running): pick the dump, restore it into
#      `keycloak_restore` with a Job, print live vs. restored figures, ask for confirmation.
#   2. Stop the writers: suspend the Flux Kustomizations `keycloak` and `keycloak-operator` (Flux would undo
#      the scale-down: a plain-manifest Kustomization reverts manual changes, see kopiur-restore.sh), suspend
#      the `keycloak-db-dump` CronJob, scale the operator and the Keycloak StatefulSet to 0 and wait until no
#      client is connected.
#   3. Swap: rename `keycloak` to `keycloak_before_<timestamp>` (kept, so the swap can be undone) and
#      `keycloak_restore` to `keycloak`, in one transaction.
#   4. Start again: resume Flux, scale the operator back up, un-suspend the CronJob, wait for Keycloak.
#
# The restore Job is derived from the live `keycloak-db-dump` CronJob (images, credentials, endpoint, bucket,
# security context), so the PostgreSQL client always matches the dump client and the per-environment values
# need no second copy here. If the script fails after phase 2 began and before the swap, it resumes everything
# and the live database is untouched; after the swap it only starts Keycloak again.
#
# The old database is NOT dropped; the end of the run prints the rollback and the cleanup commands.
#
# Usage: scripts/keycloak-db-restore.sh -e <env> [--list] [--dump <key>|latest] [-y]
#   -e, --environment  environment whose cluster is restored (required, a restore always names its target)
#   --list             only list the dumps in the bucket (key, last modified, size) and exit
#   --dump <key>       dump object to restore; default `latest` (the newest)
#   -y, --yes          do not ask for confirmation (the safety checks still apply)
# A dump from another environment must be copied into this environment's bucket first.
set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

NS="keycloak"
CLUSTER="keycloak-db"
CRONJOB="keycloak-db-dump"
OPERATOR="keycloak-operator"
STATEFULSET="keycloak"
FLUX_KS="keycloak-operator keycloak"
LIVE_DB="keycloak"
SCRATCH_DB="keycloak_restore"

usage() {
    echo "Usage: $(basename "$0") -e <env> [--list] [--dump <key>|latest] [-y]" >&2
    exit 1
}

ENV=""
LIST_ONLY=0
DUMP="latest"
YES=0
# Parses -e/--environment, --list, --dump and -y/--yes; there are no positional arguments.
while [ $# -gt 0 ]; do
    case "$1" in
        -e | --environment)
            ENV="$2"
            shift 2
            ;;
        --list)
            LIST_ONLY=1
            shift
            ;;
        --dump)
            DUMP="$2"
            shift 2
            ;;
        -y | --yes)
            YES=1
            shift
            ;;
        -h | --help) usage ;;
        *) unknown_flag "$1" ;;
    esac
done

validate_environment "${ENV}"
CTX=$(kubecontext_for_environment "${ENV}")
LOG_CTX="${CTX}"

# State the exit trap needs to know whether to undo phase 2.
SUSPENDED=0
RESUMED=0
ORIG_OPERATOR_REPLICAS=""
ORIG_CRON_SUSPEND=""
# Flux Kustomizations this run suspended (one that was suspended already stays suspended).
SUSPENDED_KS=""

# kubectl in the Keycloak namespace of the target cluster.
kc() {
    kubectl --context "${CTX}" -n "${NS}" "$@"
}

# Runs psql as the PostgreSQL superuser inside the primary's pod (local socket, peer authentication), so no
# superuser secret is needed. $1 is the database to connect to, the SQL is read from stdin.
psql_su() {
    primary=$(kc get cluster "${CLUSTER}" -o jsonpath='{.status.currentPrimary}')
    kc exec -i "${primary}" -c postgres -- psql -X -q -v ON_ERROR_STOP=1 -U postgres -d "$1" -At
}

# Prints the result of one SQL statement ($2) run against database $1 as the superuser.
sql_value() {
    printf '%s\n' "$2" | psql_su "$1"
}

# Asks a yes/no question; always yes with -y. Exits when declined.
confirm() {
    [ "${YES}" -eq 1 ] && return 0
    if ! gum confirm "$1"; then
        log warn "declined, nothing changed beyond the scratch database"
        exit 1
    fi
}

# Seconds since the start of the run, for the timings the restore drill records.
elapsed() {
    echo $(($(date +%s) - START))
}

# Builds a one-shot Job from the live dump CronJob and prints it as JSON. $1 is the Job name, $2 the mode:
# `list` runs an S3 listing in the aws-cli container; `load` downloads dump $3 and `pg_restore`s it into
# database $4. Image, credentials, endpoint, bucket and security context are inherited from the CronJob.
build_job() {
    kc get cronjob "${CRONJOB}" -o json | jq \
        --arg name "$1" --arg mode "$2" --arg key "${3:-}" --arg db "${4:-}" '
        .spec.jobTemplate.spec.template.spec as $pod
        | ($pod.containers[] | select(.name == "upload")) as $aws
        | ($pod.initContainers[] | select(.name == "dump")) as $pg
        | {
            apiVersion: "batch/v1", kind: "Job",
            metadata: {name: $name, namespace: .metadata.namespace,
                       labels: {"app.kubernetes.io/name": "keycloak-db-restore"}},
            spec: {backoffLimit: 0, activeDeadlineSeconds: 900, ttlSecondsAfterFinished: 86400,
                   template: {spec: (
                     if $mode == "list" then
                       $pod | del(.initContainers) | .containers = [$aws + {name: "list", command: ["/bin/sh", "-ec",
                         "aws s3api list-objects-v2 --bucket \"${BUCKET}\" --query \"sort_by(Contents,&LastModified)[].[Key,LastModified,Size]\" --output text"]}]
                     else
                       $pod
                       | .initContainers = [$aws + {name: "download", command: ["/bin/sh", "-ec",
                           "aws s3 cp \"s3://${BUCKET}/${DUMP_KEY}\" /dump/keycloak.dump --only-show-errors; test -s /dump/keycloak.dump"],
                           env: ($aws.env + [{name: "DUMP_KEY", value: $key}])}]
                       | .containers = [$pg + {name: "restore",
                           command: ["pg_restore", "--no-owner", "--exit-on-error", "--dbname=" + $db, "/dump/keycloak.dump"]}]
                     end)}}}'
}

# Creates the Job $1 (JSON on stdin) and waits up to $2 seconds for it to succeed or fail; its logs are
# shown at debug level on success and always on failure. Returns non-zero when the Job failed or timed out.
run_job() {
    kc create -f - >/dev/null || return 1
    waited=0
    while [ "${waited}" -lt "$2" ]; do
        ok=$(kc get job "$1" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)
        bad=$(kc get job "$1" -o jsonpath='{.status.failed}' 2>/dev/null || true)
        [ -n "${ok}" ] && break
        [ -n "${bad}" ] && break
        sleep 3
        waited=$((waited + 3))
    done
    if [ -n "${ok:-}" ]; then
        log_debug_output "$(kc logs "job/$1" --all-containers --prefix 2>&1 || true)"
        return 0
    fi
    # A failed or timed-out Job: show its logs unconditionally, debug-level lines are hidden by default.
    kc logs "job/$1" --all-containers --prefix >&2 2>&1 || true
    return 1
}

# Polls until the command given as arguments succeeds, for at most $1 seconds (checked every 3 s).
wait_for() {
    limit="$1"
    shift
    waited=0
    until "$@"; do
        [ "${waited}" -ge "${limit}" ] && return 1
        sleep 3
        waited=$((waited + 3))
    done
}

# True when workload $2 (a `deployment` or `statefulset`, kind in $1) has no replicas left; an unset
# status.replicas counts as none.
scaled_down() {
    replicas=$(kc get "$1" "$2" -o jsonpath='{.status.replicas}')
    [ -z "${replicas}" ] || [ "${replicas}" = "0" ]
}

# True when no client other than this query is connected to either database of the restore.
no_clients() {
    n=$(sql_value postgres "select count(*) from pg_stat_activity where datname in ('${LIVE_DB}','${SCRATCH_DB}') and pid <> pg_backend_pid();")
    [ "${n}" = "0" ]
}

# True when no Job of the dump CronJob is still running.
no_active_dump() {
    [ -z "$(kc get cronjob "${CRONJOB}" -o jsonpath='{.status.active[*].name}')" ]
}

# Undoes phase 2: resumes the Flux Kustomizations this run suspended, restores the operator replicas and the
# CronJob suspend flag. Safe to call twice (RESUMED guards it).
resume_all() {
    [ "${RESUMED}" -eq 1 ] && return 0
    RESUMED=1
    for ks in ${SUSPENDED_KS}; do
        flux --context "${CTX}" resume kustomization "${ks}"
    done
    # Flux restores the operator's replicas on its own reconcile, which can be an hour away; do it now.
    kc scale deployment "${OPERATOR}" --replicas="${ORIG_OPERATOR_REPLICAS}"
    kc patch cronjob "${CRONJOB}" --type merge -p "{\"spec\":{\"suspend\":${ORIG_CRON_SUSPEND}}}" >/dev/null
}

# Exit trap: if phase 2 started and nothing resumed yet (any failure, Ctrl-C, declined prompt), put the
# environment back the way it was.
cleanup() {
    if [ "${SUSPENDED}" -eq 1 ] && [ "${RESUMED}" -eq 0 ]; then
        log warn "leaving early, resuming Flux, the operator and the dump CronJob"
        resume_all || log error "resuming failed, do it by hand (flux resume kustomization keycloak-operator keycloak; scale the operator; un-suspend the CronJob)"
    fi
}
# Turn signals into an exit so that the EXIT trap runs on Ctrl-C as well.
trap 'exit 130' INT TERM HUP
trap cleanup EXIT

START=$(date +%s)
TS=$(date -u +%Y%m%d-%H%M%S)

if ! kc get cronjob "${CRONJOB}" >/dev/null 2>&1; then
    log fatal "CronJob not found, is the Keycloak unit registered in this environment?" "cronjob" "${CRONJOB}" "namespace" "${NS}"
    exit 1
fi

if [ "$(kc get cluster "${CLUSTER}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" != "True" ]; then
    log fatal "the CloudNativePG cluster is not Ready; a lost or broken instance has to be recreated first (docs/keycloak-backup-restore.md)" "cluster" "${CLUSTER}"
    exit 1
fi

# --- Phase 1: select and verify -------------------------------------------------------------------------

log info "Listing the dumps" "phase" "1/4"
build_job "keycloak-db-restore-list-${TS}" list | run_job "keycloak-db-restore-list-${TS}" 120 || {
    log fatal "could not list the bucket, see the Job logs above"
    exit 1
}
DUMPS=$(kc logs "job/keycloak-db-restore-list-${TS}" 2>/dev/null)
printf '%s\n' "${DUMPS}"

if [ "${LIST_ONLY}" -eq 1 ]; then
    exit 0
fi

if [ "${DUMP}" = "latest" ]; then
    DUMP=$(printf '%s\n' "${DUMPS}" | tail -n 1 | cut -f1)
fi
if ! printf '%s\n' "${DUMPS}" | cut -f1 | grep -qFx "${DUMP}"; then
    log fatal "dump not found in the bucket" "dump" "${DUMP}"
    exit 1
fi
log info "Selected dump" "dump" "${DUMP}"

# A scratch database left behind by an earlier aborted run is safe to replace: only this script uses the name.
if [ -n "$(sql_value postgres "select 1 from pg_database where datname = '${SCRATCH_DB}';")" ]; then
    log warn "dropping the scratch database of an earlier run" "database" "${SCRATCH_DB}"
    sql_value postgres "drop database ${SCRATCH_DB};" >/dev/null
fi
sql_value postgres "create database ${SCRATCH_DB} owner keycloak;" >/dev/null

log info "Restoring the dump into the scratch database (Keycloak keeps running)" "phase" "1/4" "database" "${SCRATCH_DB}"
build_job "keycloak-db-restore-${TS}" load "${DUMP}" "${SCRATCH_DB}" | run_job "keycloak-db-restore-${TS}" 600 || {
    log fatal "restoring into the scratch database failed, the live database was not touched"
    sql_value postgres "drop database ${SCRATCH_DB};" >/dev/null || true
    exit 1
}

tables_live=$(sql_value "${LIVE_DB}" "select count(*) from information_schema.tables where table_schema = 'public';")
tables_new=$(sql_value "${SCRATCH_DB}" "select count(*) from information_schema.tables where table_schema = 'public';")
realms_live=$(sql_value "${LIVE_DB}" "select coalesce(string_agg(name, ',' order by name), '') from realm;")
realms_new=$(sql_value "${SCRATCH_DB}" "select coalesce(string_agg(name, ',' order by name), '') from realm;")
users_live=$(sql_value "${LIVE_DB}" "select count(*) from user_entity;")
users_new=$(sql_value "${SCRATCH_DB}" "select count(*) from user_entity;")
log info "Live database" "tables" "${tables_live}" "realms" "${realms_live}" "users" "${users_live}"
log info "Restored dump" "tables" "${tables_new}" "realms" "${realms_new}" "users" "${users_new}"
if [ -z "${realms_new}" ]; then
    log fatal "the restored database has no realm, refusing to continue; the live database was not touched"
    exit 1
fi
log info "Phase 1 done" "seconds" "$(elapsed)"

confirm "Replace the live database with this dump? Keycloak will be down until it is swapped."

# --- Phase 2: stop the writers --------------------------------------------------------------------------

ORIG_OPERATOR_REPLICAS=$(kc get deployment "${OPERATOR}" -o jsonpath='{.spec.replicas}')
ORIG_CRON_SUSPEND=$(kc get cronjob "${CRONJOB}" -o jsonpath='{.spec.suspend}')
ORIG_CRON_SUSPEND="${ORIG_CRON_SUSPEND:-false}"

log info "Suspending Flux and the dump CronJob" "phase" "2/4"
SUSPENDED=1
for ks in ${FLUX_KS}; do
    if [ "$(kubectl --context "${CTX}" -n flux-system get kustomizations.kustomize.toolkit.fluxcd.io "${ks}" -o jsonpath='{.spec.suspend}')" != "true" ]; then
        flux --context "${CTX}" suspend kustomization "${ks}"
        SUSPENDED_KS="${SUSPENDED_KS} ${ks}"
    fi
done
kc patch cronjob "${CRONJOB}" --type merge -p '{"spec":{"suspend":true}}' >/dev/null
wait_for 300 no_active_dump || {
    log fatal "a dump Job is still running after 5 minutes"
    exit 1
}

log info "Scaling down the operator and Keycloak" "phase" "2/4"
kc scale deployment "${OPERATOR}" --replicas=0
wait_for 120 scaled_down deployment "${OPERATOR}" || {
    log fatal "the operator did not scale down"
    exit 1
}
if kc get statefulset "${STATEFULSET}" >/dev/null 2>&1; then
    kc scale statefulset "${STATEFULSET}" --replicas=0
    wait_for 180 scaled_down statefulset "${STATEFULSET}" || {
        log fatal "Keycloak did not scale down"
        exit 1
    }
fi
wait_for 120 no_clients || {
    log fatal "clients are still connected to the databases, refusing to swap"
    exit 1
}
log info "Writers stopped" "seconds" "$(elapsed)"

# --- Phase 3: swap --------------------------------------------------------------------------------------

OLD_DB="keycloak_before_$(echo "${TS}" | tr '-' '_')"
log info "Swapping the databases" "phase" "3/4" "kept_as" "${OLD_DB}"
printf 'begin;\nalter database %s rename to %s;\nalter database %s rename to %s;\ncommit;\n' \
    "${LIVE_DB}" "${OLD_DB}" "${SCRATCH_DB}" "${LIVE_DB}" | psql_su postgres

# --- Phase 4: start again -------------------------------------------------------------------------------

log info "Resuming Flux and starting Keycloak" "phase" "4/4"
resume_all
kc wait keycloak/keycloak --for=condition=Ready --timeout=600s || log error "Keycloak is not Ready within 10 minutes, check the pod and operator logs"
log info "Done" "seconds" "$(elapsed)" "dump" "${DUMP}"

cat <<EOF >&2

The previous database is kept as ${OLD_DB}. After checking the login:
  drop it:     echo "drop database ${OLD_DB};" | kubectl --context ${CTX} -n ${NS} exec -i \$(kubectl --context ${CTX} -n ${NS} get cluster ${CLUSTER} -o jsonpath='{.status.currentPrimary}') -c postgres -- psql -U postgres
  roll back:   stop Keycloak as above, then rename ${LIVE_DB} to a spare name and ${OLD_DB} back to ${LIVE_DB} (docs/keycloak-backup-restore.md#roll-back)
EOF
