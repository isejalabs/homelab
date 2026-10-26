#!/bin/sh
# Measures how long Keycloak logins are interrupted when the node running its database is drained (or, with
# --observe, when something else takes the node away: a reboot, a VM shutdown, a node failure). It is the
# measurement half of the availability drill in docs/keycloak-drain-drill.md.
#
# While the disturbance runs, two probes hit the environment's Keycloak from this machine every few seconds:
#   discovery  GET  /realms/master/.well-known/openid-configuration  expected 200 (Keycloak pod serves requests)
#   login      POST /realms/master/protocol/openid-connect/token     expected 401 (unknown user, so the token
#              endpoint has to look the user up; 5xx or no answer means the login path is down). Nothing is
#              created: the request names a user that does not exist, with a made-up password.
# From the two probe logs it prints the outage windows, their total and longest duration, and a timeline of the
# pod events and pod condition changes since the start (eviction, image pull, database ready, Keycloak ready).
# The raw data (probe logs, events, pods, drain output, report) is kept in the output directory as evidence.
#
# Default mode cordons and drains the node of the CloudNativePG primary (or --node), waits until both probes
# have been healthy again for a few samples, and uncordons the node. With --observe nothing is changed: the
# script starts measuring and waits until an outage has been seen and is over. `prod` is refused: the drill
# disturbs a live cluster. Before a drain, the script reports the factors that distorted the first
# measurement (DiskPressure on the nodes, whether the images are listed on the other nodes) so they can be
# fixed or accepted first.
#
# Exits 0 when the login probe stayed within --target (or no target was given), 2 when it exceeded it, 1 on
# any other failure. Manual only (disrupts the cluster, needs a kubecontext and network access to Keycloak).
#
# Usage: scripts/keycloak-drain-drill.sh -e <env> [--node <node>] [--observe] [--target <seconds>]
#                                        [--interval <seconds>] [--timeout <seconds>] [--out <dir>] [--yes]
set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

NAMESPACE="keycloak"
KEYCLOAK_POD="keycloak-0"
DB_CLUSTER="keycloak-db"
# Consecutive healthy samples that count as recovered, and the time after the end of a drain within which a
# drill without any outage is accepted as "the drain did not touch Keycloak".
STABLE_SAMPLES=5
GRACE_SECONDS=60
BASELINE_SECONDS=10

# Prints the synopsis and exits non-zero.
usage() {
    echo "Usage: $(basename "$0") -e <env> [--node <node>] [--observe] [--target <seconds>] [--interval <seconds>] [--timeout <seconds>] [--out <dir>] [--yes]" >&2
    exit 1
}

# Exits fatal (via `log`) unless every tool the script shells out to is present.
require_tools() {
    for tool in kubectl curl jq gum; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            log fatal "required tool not found" "tool" "${tool}"
            exit 1
        fi
    done
}

# kubectl against the environment's kubecontext.
kc() {
    kubectl --context "${CTX}" "$@"
}

# Prints the current time as epoch seconds.
now() {
    date +%s
}

# Stops the probes and, if this run cordoned a node, uncordons it again. Runs on every exit, so a Ctrl-C in the
# middle of a drain does not leave the node unschedulable.
cleanup() {
    for pid in ${PROBE_PIDS}; do
        kill "${pid}" 2>/dev/null || true
    done
    if [ "${CORDONED}" -eq 1 ]; then
        log warn "uncordoning node" "node" "${NODE}"
        kc uncordon "${NODE}" >/dev/null 2>&1 || log error "could not uncordon, do it by hand" "node" "${NODE}"
        CORDONED=0
    fi
}

# Runs one probe in a loop until killed, appending "<epoch>\t<http status>" to $OUT/<name>.tsv per sample:
# $1 name, $2 HTTP method, $3 URL, optional $4 form body. Status 000 means curl got no answer within 3 s.
probe_loop() {
    while true; do
        if [ -n "${4:-}" ]; then
            code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 -X "$2" --data "$4" "$3" 2>/dev/null) || true
        else
            code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 -X "$2" "$3" 2>/dev/null) || true
        fi
        printf '%s\t%s\n' "$(now)" "${code:-000}" >>"${OUT}/$1.tsv"
        sleep "${INTERVAL}"
    done
}

# Exits 0 when the last STABLE_SAMPLES samples of probe $1 (file) all returned the expected status $2.
probe_healthy() {
    tail -n "${STABLE_SAMPLES}" "${OUT}/$1.tsv" | awk -F '\t' -v n="${STABLE_SAMPLES}" -v ok="$2" '$2 == ok { c++ } END { exit !(NR == n && c == n) }'
}

# Exits 0 when probe $1 (file) has returned anything but the expected status $2 since the start of the drill.
probe_failed_once() {
    awk -F '\t' -v t0="${T0}" -v ok="$2" '$1 >= t0 && $2 != ok { f = 1 } END { exit !f }' "${OUT}/$1.tsv"
}

# Prints the preflight report: where the pods run, DiskPressure per node, and for each image of the pods on the
# node whether the other nodes list it (a missing entry means a cold image pull after the move). The kubelet
# reports at most 50 images per node, so "not listed" is a strong hint, not proof.
preflight_report() {
    echo "Pods in ${NAMESPACE}:"
    kc -n "${NAMESPACE}" get pods -o wide
    echo
    echo "Nodes (DiskPressure):"
    kc get nodes -o json | jq -r '.items[] | "  \(.metadata.name)\tDiskPressure=\(first(.status.conditions[] | select(.type == "DiskPressure") | .status))\tunschedulable=\(.spec.unschedulable // false)"'
    echo
    echo "Images of the pods on ${NODE}, as listed by the other nodes:"
    kc -n "${NAMESPACE}" get pods -o json | jq -r --arg n "${NODE}" '[.items[] | select(.spec.nodeName == $n) | .spec.containers[].image] | unique[]' |
        while IFS= read -r image; do
            kc get nodes -o json | jq -r --arg img "${image}" --arg n "${NODE}" '.items[] | select(.metadata.name != $n) | "  \($img)\t\(.metadata.name)\t\(if any(.status.images[]?; (.names // []) | index($img)) then "listed" else "not listed" end)"'
        done
}

# Prints the outage windows of one probe as JSON on stdout: $1 file, $2 expected status. A window runs from the
# first failed sample to the first healthy one after it (resolution: the probe interval); one still open at the
# end of the data is closed at the last sample and flagged. Offsets are seconds after the start of the drill.
analyze_probe() {
    jq -R -s --arg ok "$2" --argjson t0 "${T0}" '
        [split("\n")[] | select(length > 0) | split("\t") | {t: (.[0] | tonumber), ok: (.[1] == $ok)}] as $s
        | ($s | reduce .[] as $x ({w: [], open: null};
              if $x.ok then
                  (if .open != null then .w += [{start: .open, end: $x.t, open: false}] | .open = null else . end)
              else
                  (if .open == null then .open = $x.t else . end)
              end)) as $r
        | ($r.w + (if $r.open != null then [{start: $r.open, end: $s[-1].t, open: true}] else [] end)
           | map(. + {offset: (.start - $t0), duration: (.end - .start)})) as $w
        | {samples: ($s | length), failed: ($s | map(select(.ok | not)) | length), windows: $w,
           total: ($w | map(.duration) | add // 0), longest: ($w | map(.duration) | max // 0)}' "${OUT}/$1.tsv"
}

# Prints the timeline since the start of the drill: events of the namespace plus the times pods became
# scheduled, initialized and ready, merged and sorted. Offsets are seconds after the start.
timeline() {
    jq -n -r --argjson t0 "${T0}" --slurpfile ev "${OUT}/events.json" --slurpfile pods "${OUT}/pods.json" '
        def ts: sub("\\.[0-9]+"; "") | fromdateiso8601;
        [($ev[0].items[] | (.eventTime // .lastTimestamp // .firstTimestamp) as $t | select($t != null)
              | {t: ($t | ts), who: "\(.involvedObject.kind)/\(.involvedObject.name)", what: .reason, msg: (.message // .note // "")}),
         ($pods[0].items[] | .metadata.name as $n | .status.conditions[]? | select(.status == "True")
              | {t: (.lastTransitionTime | ts), who: "Pod/\($n)", what: "condition \(.type)", msg: ""})]
        | map(select(.t >= $t0 - 5)) | sort_by(.t)[]
        | "  \(if .t < $t0 then "-" else "+" end)\((.t - $t0) | fabs | floor)s\t\(.who)\t\(.what)\t\(.msg)"' | column -t -s "$(printf '\t')"
}

# Prints the whole report: setup, outage windows per probe, timeline and the verdict against --target.
report() {
    echo "Keycloak drain drill, environment ${ENV}, ${MODE} of node ${NODE}"
    echo "Started $(date -r "${T0}" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date -d "@${T0}" '+%Y-%m-%d %H:%M:%S %Z'), measured for $((T_END - T0))s, probe interval ${INTERVAL}s"
    [ -n "${DRAIN_SECONDS:-}" ] && echo "kubectl drain returned after ${DRAIN_SECONDS}s"
    for probe in discovery login; do
        echo
        jq -r --arg p "${probe}" '"Probe \($p): \(.samples) samples, \(.failed) failed, outage total \(.total)s, longest \(.longest)s" + (if .windows == [] then ", no outage" else "" end), (.windows[] | "  down +\(.offset)s for \(.duration)s" + (if .open then " (still down at the end of the data)" else "" end))' "${OUT}/${probe}.summary.json"
    done
    echo
    echo "Timeline (offsets from the start):"
    timeline
    echo
    LOGIN_TOTAL=$(jq -r .total "${OUT}/login.summary.json")
    if [ -z "${TARGET}" ]; then
        echo "Verdict: login interrupted for ${LOGIN_TOTAL}s in total (no --target given, nothing to compare with)"
    elif [ "${LOGIN_TOTAL}" -le "${TARGET}" ]; then
        echo "Verdict: PASS, login interrupted for ${LOGIN_TOTAL}s in total, target ${TARGET}s"
    else
        echo "Verdict: FAIL, login interrupted for ${LOGIN_TOTAL}s in total, target ${TARGET}s"
    fi
}

ENV=""
NODE=""
OBSERVE=0
TARGET=""
INTERVAL=2
TIMEOUT=1800
OUT=""
ASSUME_YES=0
while [ $# -gt 0 ]; do
    case "$1" in
        -e | --environment)
            ENV="$2"
            shift 2
            ;;
        --node)
            NODE="$2"
            shift 2
            ;;
        --observe)
            OBSERVE=1
            shift
            ;;
        --target)
            TARGET="$2"
            shift 2
            ;;
        --interval)
            INTERVAL="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --out)
            OUT="$2"
            shift 2
            ;;
        -y | --yes)
            ASSUME_YES=1
            shift
            ;;
        -h | --help) usage ;;
        -*) unknown_flag "$1" ;;
        *) usage ;;
    esac
done

[ -z "${ENV}" ] && usage
validate_environment "${ENV}"
if [ "${ENV}" = "prod" ]; then
    log fatal "refusing to run against prod: the drill disturbs a live cluster" "env" "${ENV}"
    exit 1
fi
require_tools

CTX=$(kubecontext_for_environment "${ENV}")
LOG_CTX="${CTX}"
PROBE_PIDS=""
CORDONED=0
trap cleanup EXIT
trap 'exit 130' INT TERM

HOST=$(kc -n "${NAMESPACE}" get keycloak keycloak -o jsonpath='{.spec.hostname.hostname}' 2>/dev/null) || HOST=""
if [ -z "${HOST}" ]; then
    log fatal "no Keycloak resource found in the cluster (is the unit registered in this environment?)" "namespace" "${NAMESPACE}"
    exit 1
fi
BASE_URL="https://${HOST}"

if [ -z "${NODE}" ]; then
    NODE=$(kc -n "${NAMESPACE}" get pods -l "cnpg.io/cluster=${DB_CLUSTER},cnpg.io/instanceRole=primary" -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null) || NODE=""
fi
if [ -z "${NODE}" ]; then
    log fatal "could not determine the node of the database primary, pass --node" "cluster" "${DB_CLUSTER}"
    exit 1
fi

[ -z "${OUT}" ] && OUT="${TMPDIR:-/tmp}/keycloak-drain-drill-${ENV}-$(date +%Y%m%dT%H%M%S)"
mkdir -p "${OUT}"
MODE="drain"
[ "${OBSERVE}" -eq 1 ] && MODE="observation"

preflight_report | tee "${OUT}/preflight.txt"
echo
if [ "$(kc -n "${NAMESPACE}" get pod "${KEYCLOAK_POD}" -o jsonpath='{.spec.nodeName}' 2>/dev/null)" = "${NODE}" ]; then
    log warn "Keycloak and the database primary run on the same node, a drain interrupts both" "node" "${NODE}"
fi

if [ "${OBSERVE}" -eq 0 ] && [ "${ASSUME_YES}" -eq 0 ]; then
    gum confirm "Cordon and drain ${NODE} in ${ENV}? Keycloak logins will be interrupted." || exit 1
fi

TOKEN_URL="${BASE_URL}/realms/master/protocol/openid-connect/token"
probe_loop discovery GET "${BASE_URL}/realms/master/.well-known/openid-configuration" &
PROBE_PIDS="$!"
probe_loop login POST "${TOKEN_URL}" "client_id=admin-cli&grant_type=password&username=drill-probe-no-such-user&password=drill-probe" &
PROBE_PIDS="${PROBE_PIDS} $!"

log info "recording a healthy baseline" "seconds" "${BASELINE_SECONDS}" "url" "${BASE_URL}"
sleep "${BASELINE_SECONDS}"
if ! probe_healthy discovery 200 || ! probe_healthy login 401; then
    log fatal "the probes are not healthy before the drill, nothing meaningful to measure (see ${OUT})" "discovery" "$(tail -n 1 "${OUT}/discovery.tsv")" "login" "$(tail -n 1 "${OUT}/login.tsv")"
    exit 1
fi

T0=$(now)
DRAIN_END=""
if [ "${OBSERVE}" -eq 0 ]; then
    log info "draining node" "node" "${NODE}"
    CORDONED=1
    kc drain "${NODE}" --ignore-daemonsets --delete-emptydir-data --timeout="${TIMEOUT}s" >"${OUT}/drain.txt" 2>&1 || {
        log error "kubectl drain failed (see ${OUT}/drain.txt)"
        exit 1
    }
    DRAIN_END=$(now)
    DRAIN_SECONDS=$((DRAIN_END - T0))
    log info "drain returned" "seconds" "${DRAIN_SECONDS}"
else
    log info "measuring now: disturb the node (drain, reboot, stop the VM), the script ends once the outage is over" "node" "${NODE}"
fi

while true; do
    elapsed=$(($(now) - T0))
    if [ "${elapsed}" -gt "${TIMEOUT}" ]; then
        log error "timed out before the probes recovered" "seconds" "${elapsed}"
        break
    fi
    if probe_healthy discovery 200 && probe_healthy login 401; then
        if probe_failed_once discovery 200 || probe_failed_once login 401; then
            break
        fi
        if [ -n "${DRAIN_END}" ] && [ $(($(now) - DRAIN_END)) -gt "${GRACE_SECONDS}" ]; then
            log warn "no outage seen within the grace period, the drain did not interrupt Keycloak" "seconds" "${GRACE_SECONDS}"
            break
        fi
    fi
    sleep 5
done
T_END=$(now)

for pid in ${PROBE_PIDS}; do kill "${pid}" 2>/dev/null || true; done
PROBE_PIDS=""
if [ "${CORDONED}" -eq 1 ]; then
    kc uncordon "${NODE}" >/dev/null
    CORDONED=0
    log info "node uncordoned" "node" "${NODE}"
fi

kc -n "${NAMESPACE}" get events -o json >"${OUT}/events.json"
kc -n "${NAMESPACE}" get pods -o json >"${OUT}/pods.json"
analyze_probe discovery 200 >"${OUT}/discovery.summary.json"
analyze_probe login 401 >"${OUT}/login.summary.json"

report | tee "${OUT}/report.txt"
log info "data kept" "dir" "${OUT}"

if [ -n "${TARGET}" ] && [ "${LOGIN_TOTAL}" -gt "${TARGET}" ]; then
    exit 2
fi
