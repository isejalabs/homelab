#!/bin/sh
# Restores the Immich database from a `pg_dump` in the environment's `<env>-immich-db` bucket, safely against a
# concurrent Flux reconcile and without deleting the running database. Works the same for a live database that
# holds wrong content and for a fresh, empty cluster (the restore drill). See docs/backup/immich-database.md for
# the procedure around this script.
#
# Why a second database in the same cluster, and not a new CloudNativePG `Cluster`: CloudNativePG can only
# bootstrap a cluster from a live PostgreSQL source or from base backups plus archived WAL; it cannot read a dump
# file from a bucket, and this cluster deliberately archives no WAL. So the dump is restored into a scratch
# database `immich_restore` next to the live `immich` and swapped in by renaming both once nothing writes. This is
# the approach of scripts/ops/keycloak/db-restore.sh, adapted to Immich (the writers are the Immich workloads).
#
# Phases:
#   1. Select and verify (non-destructive, Immich keeps running): pick the dump, restore it into `immich_restore`
#      with a Job, print live vs. restored figures (users, assets, albums, faces, extension versions), ask for
#      confirmation.
#   2. Stop the writers: suspend the Flux Kustomization `immich` (the Immich unit, if it exists) and the
#      `immich-db-dump` CronJob (and wait for a running dump), scale every Deployment and StatefulSet in the
#      namespace except Valkey to 0 and wait until no client is connected to the database. Valkey holds no state
#      worth keeping (cache and job queue) and stays up.
#   3. Swap: rename `immich` to `immich_before_<timestamp>` (kept, so the swap can be undone) and `immich_restore`
#      to `immich`, in one transaction.
#   4. Start again: resume Flux, scale the workloads back to their previous replicas, restore the CronJob's
#      suspend flag.
#
# The restore Job is derived from the live `immich-db-dump` CronJob (images, credentials, endpoint, bucket,
# security context), so the PostgreSQL client always matches the dump client. If the script fails after phase 2
# began and before the swap, it resumes everything and the live database is untouched; after the swap it only
# starts the workloads again. The old database is NOT dropped; the end of the run prints the cleanup commands.
#
# Dumps are encrypted with age (`*.dump.age`). `--identity` names the age private key file. It is put into a
# temporary Secret `immich-db-restore-identity-<timestamp>` that only the restore Job mounts, and the Secret is
# deleted again right after that Job ended (and by the exit trap).
#
# Usage: scripts/ops/immich/db-restore.sh -e <env> [--list] [--dump <key>|latest] [--identity <file>] [-y]
#   -e, --environment  environment whose cluster is restored (required, a restore always names its target)
#   --list             only list the dumps in the bucket (key, last modified, size) and exit
#   --dump <key>       dump object to restore; default `latest` (the newest)
#   --identity <file>  age private key to decrypt a `*.age` dump; a process substitution works, for example
#                      `--identity <(op read 'op://IT Infrastructure/keycloak-db age key/password')`
#   -y, --yes          do not ask for confirmation (the safety checks still apply)
# A dump from another environment must be copied into this environment's bucket first.
set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

NS="immich"
CLUSTER="immich-db"
CRONJOB="immich-db-dump"
KEEP_RUNNING="immich-valkey"
FLUX_KS="immich"
LIVE_DB="immich"
SCRATCH_DB="immich_restore"

usage() {
    echo "Usage: $(basename "$0") -e <env> [--list] [--dump <key>|latest] [--identity <file>] [-y]" >&2
    exit 1
}

ENV=""
LIST_ONLY=0
DUMP="latest"
IDENTITY=""
YES=0
# Parses -e/--environment, --list, --dump, --identity and -y/--yes; there are no positional arguments.
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
        --identity)
            IDENTITY="$2"
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
ORIG_CRON_SUSPEND=""
# Flux Kustomizations this run suspended (one that was suspended already stays suspended).
SUSPENDED_KS=""
# Workloads this run scaled down, one "<kind>/<name>=<replicas>" per line.
SCALED=""
# Name of the temporary Secret that holds the age private key while the restore Job runs (empty: none created).
IDENTITY_SECRET=""

# kubectl in the Immich namespace of the target cluster.
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

# Prints the row count of Immich table $2 in database $1, or `n/a` when the table does not exist (an empty
# database, or a table renamed by a later Immich version).
table_count() {
    sql_value "$1" "select case when to_regclass('public.$2') is null then 'n/a' else (select count(*)::text from public.$2) end;"
}

# Prints the version of PostgreSQL extension $2 in database $1, or `none` when it is not installed.
extension_version() {
    sql_value "$1" "select coalesce((select extversion from pg_extension where extname = '$2'), 'none');"
}

# Prints the figures that identify the content of database $1 on one line, for the live/restored comparison.
describe_db() {
    printf 'tables=%s users=%s assets=%s albums=%s faces=%s vchord=%s' \
        "$(sql_value "$1" "select count(*) from information_schema.tables where table_schema = 'public';")" \
        "$(table_count "$1" '"user"')" "$(table_count "$1" asset)" "$(table_count "$1" album)" \
        "$(table_count "$1" asset_face)" "$(extension_version "$1" vchord)"
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

# Shell run by the `download` container of a restore Job: fetches dump $DUMP_KEY and, for an age-encrypted one,
# decrypts it with the private key mounted from the temporary Secret. Either way the plain dump ends up in
# /dump/immich.dump. Kept in one place so build_job passes it to jq as a plain string.
DOWNLOAD_SCRIPT='case "${DUMP_KEY}" in
  *.age)
    aws s3 cp "s3://${BUCKET}/${DUMP_KEY}" /dump/immich.dump.age --only-show-errors
    /age/age -d -i /identity/age.key -o /dump/immich.dump /dump/immich.dump.age
    rm /dump/immich.dump.age
    ;;
  *) aws s3 cp "s3://${BUCKET}/${DUMP_KEY}" /dump/immich.dump --only-show-errors ;;
esac
test -s /dump/immich.dump'

# Builds a one-shot Job from the live dump CronJob and prints it as JSON. $1 is the Job name, $2 the mode:
# `list` runs an S3 listing in the aws-cli container; `load` downloads dump $3 (decrypting it when its key ends
# in `.age`, with the Secret ${IDENTITY_SECRET}) and `pg_restore`s it into database $4. Image, credentials,
# endpoint, bucket and security context are inherited from the CronJob; an encrypted dump also inherits the
# CronJob's `fetch-age` step, which provides the age binary.
build_job() {
    kc get cronjob "${CRONJOB}" -o json | jq \
        --arg name "$1" --arg mode "$2" --arg key "${3:-}" --arg db "${4:-}" \
        --arg identity "${IDENTITY_SECRET}" --arg download "${DOWNLOAD_SCRIPT}" '
        .spec.jobTemplate.spec.template.spec as $pod
        | ($pod.containers[] | select(.name == "upload")) as $aws
        | ($pod.initContainers[] | select(.name == "dump")) as $pg
        | ($pod.initContainers[] | select(.name == "fetch-age")) as $fetch
        | ($key | endswith(".age")) as $encrypted
        | {
            apiVersion: "batch/v1", kind: "Job",
            metadata: {name: $name, namespace: .metadata.namespace,
                       labels: {"app.kubernetes.io/name": "immich-db-restore"}},
            spec: {backoffLimit: 0, activeDeadlineSeconds: 3600, ttlSecondsAfterFinished: 86400,
                   template: {spec: (
                     if $mode == "list" then
                       $pod | del(.initContainers) | .containers = [$aws + {name: "list", command: ["/bin/sh", "-ec",
                         "aws s3api list-objects-v2 --bucket \"${BUCKET}\" --query \"sort_by(Contents,&LastModified)[].[Key,LastModified,Size]\" --output text"]}]
                     else
                       $pod
                       | .initContainers = (
                           (if $encrypted then [$fetch] else [] end)
                           + [$aws + {name: "download", command: ["/bin/sh", "-ec", $download],
                               env: ($aws.env + [{name: "DUMP_KEY", value: $key}]),
                               volumeMounts: ($aws.volumeMounts
                                              + (if $encrypted then [{name: "identity", mountPath: "/identity", readOnly: true}] else [] end))}])
                       | .volumes += (if $encrypted then [{name: "identity", secret: {secretName: $identity}}] else [] end)
                       | .containers = [$pg + {name: "restore",
                           command: ["pg_restore", "--no-owner", "--exit-on-error", "--dbname=" + $db, "/dump/immich.dump"]}]
                     end)}}}'
}

# Deletes the temporary Secret with the age private key, if one was created. Safe to call repeatedly.
delete_identity_secret() {
    [ -n "${IDENTITY_SECRET}" ] || return 0
    kc delete secret "${IDENTITY_SECRET}" --ignore-not-found >/dev/null
}

# Reads a Job JSON from stdin, creates it and waits up to $2 seconds for the Job named $1 to succeed or fail; its
# logs are shown at debug level on success and always on failure. Returns non-zero when the Job failed or timed out.
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

# True when no Pod of the namespace that is not part of the database or Valkey is still running. The Pods of the
# Jobs of this restore and of the CloudNativePG instance are not counted.
writers_gone() {
    [ -z "$(kc get pods -o json | jq -r --arg valkey "${KEEP_RUNNING}" --arg cluster "${CLUSTER}" '
        .items[]
        | select(.status.phase == "Running" or .status.phase == "Pending")
        | select((.metadata.labels["cnpg.io/cluster"] // "") != $cluster)
        | select((.metadata.labels["app.kubernetes.io/name"] // "") != $valkey)
        | select(.metadata.ownerReferences // [] | map(.kind) | index("Job") | not)
        | .metadata.name')" ]
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

# Undoes phase 2: resumes the Flux Kustomizations this run suspended, scales the workloads this run scaled down
# back to their replicas and restores the CronJob suspend flag. Safe to call twice (RESUMED guards it).
resume_all() {
    [ "${RESUMED}" -eq 1 ] && return 0
    RESUMED=1
    for ks in ${SUSPENDED_KS}; do
        flux --context "${CTX}" resume kustomization "${ks}"
    done
    # Flux restores replicas on its own reconcile, which can be an hour away; do it now.
    for item in ${SCALED}; do
        kc scale "${item%%=*}" --replicas="${item##*=}"
    done
    kc patch cronjob "${CRONJOB}" --type merge -p "{\"spec\":{\"suspend\":${ORIG_CRON_SUSPEND}}}" >/dev/null
}

# Exit trap: if phase 2 started and nothing resumed yet (any failure, Ctrl-C, declined prompt), put the
# environment back the way it was.
cleanup() {
    delete_identity_secret || log error "could not delete the temporary age Secret, delete it by hand" "secret" "${IDENTITY_SECRET}"
    if [ "${SUSPENDED}" -eq 1 ] && [ "${RESUMED}" -eq 0 ]; then
        log warn "leaving early, resuming Flux, the workloads and the dump CronJob"
        resume_all || log error "resuming failed, do it by hand (flux resume kustomization ${FLUX_KS}; scale the workloads back; un-suspend the CronJob)"
    fi
}
# Turn signals into an exit so that the EXIT trap runs on Ctrl-C as well.
trap 'exit 130' INT TERM HUP
trap cleanup EXIT

START=$(date +%s)
TS=$(date -u +%Y%m%d-%H%M%S)

if ! kc get cronjob "${CRONJOB}" >/dev/null 2>&1; then
    log fatal "CronJob not found, is the immich-db unit registered in this environment?" "cronjob" "${CRONJOB}" "namespace" "${NS}"
    exit 1
fi

if [ "$(kc get cluster "${CLUSTER}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" != "True" ]; then
    log fatal "the CloudNativePG cluster is not Ready; a lost or broken instance has to be recreated first (docs/backup/immich-database.md)" "cluster" "${CLUSTER}"
    exit 1
fi

# --- Phase 1: select and verify -------------------------------------------------------------------------

log info "Listing the dumps" "phase" "1/4"
build_job "immich-db-restore-list-${TS}" list | run_job "immich-db-restore-list-${TS}" 120 || {
    log fatal "could not list the bucket, see the Job logs above"
    exit 1
}
DUMPS=$(kc logs "job/immich-db-restore-list-${TS}" 2>/dev/null)
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

# An encrypted dump needs the private key; refuse before anything is created, with the live database untouched.
case "${DUMP}" in
    *.age)
        if [ -z "${IDENTITY}" ]; then
            log fatal "the dump is age-encrypted, pass the private key with --identity <file>" "dump" "${DUMP}"
            exit 1
        fi
        if [ ! -r "${IDENTITY}" ]; then
            log fatal "cannot read the age identity file" "file" "${IDENTITY}"
            exit 1
        fi
        ;;
esac

# A scratch database left behind by an earlier aborted run is safe to replace: only this script uses the name.
if [ -n "$(sql_value postgres "select 1 from pg_database where datname = '${SCRATCH_DB}';")" ]; then
    log warn "dropping the scratch database of an earlier run" "database" "${SCRATCH_DB}"
    sql_value postgres "drop database ${SCRATCH_DB};" >/dev/null
fi
sql_value postgres "create database ${SCRATCH_DB} owner immich;" >/dev/null

log info "Restoring the dump into the scratch database (Immich keeps running)" "phase" "1/4" "database" "${SCRATCH_DB}"
case "${DUMP}" in
    *.age)
        IDENTITY_SECRET="immich-db-restore-identity-${TS}"
        kc create secret generic "${IDENTITY_SECRET}" --from-file=age.key="${IDENTITY}" >/dev/null
        ;;
esac
RESTORE_START=$(date +%s)
build_job "immich-db-restore-${TS}" load "${DUMP}" "${SCRATCH_DB}" | run_job "immich-db-restore-${TS}" 3600 || {
    delete_identity_secret || true
    log fatal "restoring into the scratch database failed, the live database was not touched"
    sql_value postgres "drop database ${SCRATCH_DB};" >/dev/null || true
    exit 1
}
delete_identity_secret
RESTORE_SECONDS=$(($(date +%s) - RESTORE_START))

live=$(describe_db "${LIVE_DB}")
restored=$(describe_db "${SCRATCH_DB}")
log info "Live database" "figures" "${live}"
log info "Restored dump" "figures" "${restored}" "restore_seconds" "${RESTORE_SECONDS}"
if [ "$(table_count "${SCRATCH_DB}" '"user"')" = "n/a" ]; then
    log fatal "the restored database has no user table, refusing to continue; the live database was not touched"
    exit 1
fi
log info "Phase 1 done" "seconds" "$(elapsed)"

confirm "Replace the live database with this dump? Immich will be down until it is swapped."

# --- Phase 2: stop the writers --------------------------------------------------------------------------

ORIG_CRON_SUSPEND=$(kc get cronjob "${CRONJOB}" -o jsonpath='{.spec.suspend}')
ORIG_CRON_SUSPEND="${ORIG_CRON_SUSPEND:-false}"

log info "Suspending Flux and the dump CronJob" "phase" "2/4"
SUSPENDED=1
for ks in ${FLUX_KS}; do
    # the Immich unit does not exist in every environment (or yet); nothing to suspend then
    suspended=$(kubectl --context "${CTX}" -n flux-system get kustomizations.kustomize.toolkit.fluxcd.io "${ks}" -o jsonpath='{.spec.suspend}' 2>/dev/null) || continue
    if [ "${suspended}" != "true" ]; then
        flux --context "${CTX}" suspend kustomization "${ks}"
        SUSPENDED_KS="${SUSPENDED_KS} ${ks}"
    fi
done
kc patch cronjob "${CRONJOB}" --type merge -p '{"spec":{"suspend":true}}' >/dev/null
wait_for 300 no_active_dump || {
    log fatal "a dump Job is still running after 5 minutes"
    exit 1
}

log info "Scaling down the Immich workloads" "phase" "2/4"
SCALED=$(kc get deployments,statefulsets -o json | jq -r --arg keep "${KEEP_RUNNING}" '
    .items[]
    | select(.metadata.name != $keep)
    | select((.spec.replicas // 1) > 0)
    | "\(.kind | ascii_downcase)/\(.metadata.name)=\(.spec.replicas // 1)"')
for item in ${SCALED}; do
    kc scale "${item%%=*}" --replicas=0
done
wait_for 180 writers_gone || {
    log fatal "Immich Pods are still running after 3 minutes"
    exit 1
}
wait_for 120 no_clients || {
    log fatal "clients are still connected to the databases, refusing to swap"
    exit 1
}
log info "Writers stopped" "seconds" "$(elapsed)"

# --- Phase 3: swap --------------------------------------------------------------------------------------

OLD_DB="immich_before_$(echo "${TS}" | tr '-' '_')"
log info "Swapping the databases" "phase" "3/4" "kept_as" "${OLD_DB}"
printf 'begin;\nalter database %s rename to %s;\nalter database %s rename to %s;\ncommit;\n' \
    "${LIVE_DB}" "${OLD_DB}" "${SCRATCH_DB}" "${LIVE_DB}" | psql_su postgres

# --- Phase 4: start again -------------------------------------------------------------------------------

log info "Resuming Flux and starting the Immich workloads" "phase" "4/4"
resume_all
log info "Done" "seconds" "$(elapsed)" "restore_seconds" "${RESTORE_SECONDS}" "dump" "${DUMP}"

cat <<EOF >&2

The previous database is kept as ${OLD_DB}. After checking albums, faces and users in Immich:
  drop it:     echo "drop database ${OLD_DB};" | kubectl --context ${CTX} -n ${NS} exec -i \$(kubectl --context ${CTX} -n ${NS} get cluster ${CLUSTER} -o jsonpath='{.status.currentPrimary}') -c postgres -- psql -U postgres
  roll back:   stop the Immich workloads as above, then rename ${LIVE_DB} to a spare name and ${OLD_DB} back to ${LIVE_DB} (docs/backup/immich-database.md#roll-back)
EOF
