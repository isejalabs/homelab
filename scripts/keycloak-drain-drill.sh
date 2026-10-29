#!/bin/sh
# Measures how long Keycloak logins are interrupted when the node running its database is drained (or, with
# --observe, when something else takes the node away: a reboot, a VM shutdown, a node failure). It is the
# measurement half of the availability drill in docs/keycloak-drain-drill.md.
#
# While the disturbance runs, two probes hit the environment's Keycloak from this machine every few seconds:
#   discovery  GET  /realms/master/.well-known/openid-configuration  expected 200 (Keycloak pod serves requests)
#   login      POST /realms/master/protocol/openid-connect/token     expected 400 with error
#              `invalid_grant` (unknown user, so the token endpoint has to look the user up and reject the
#              credentials; 5xx or no answer means the login path is down). Nothing is created: the request
#              names a user that does not exist, with a made-up password.
# From the two probe logs it prints the outage windows, their total and longest duration, and a timeline of the
# pod events and pod condition changes since the start (eviction, image pull, database ready, Keycloak ready).
# The raw data (probe logs, events, pods, drain output, report) is kept in the output directory as evidence.
#
# Default mode cordons and drains the node of the CloudNativePG primary (or --node). The drain runs in the
# background while the probes keep measuring, so a drain that stalls (for example on the PodDisruptionBudget of
# Longhorn's instance-manager) or fails does not stop the measurement; the script waits until the drain has
# ended and both probes have been healthy again for a few samples, then uncordons the node (retrying while the
# API server is unreachable). With --observe nothing is changed: the script starts measuring and waits until an
# outage has been seen and is over. `prod` is refused: the drill
# disturbs a live cluster, and nothing starts unless the control plane is healthy (API server ready, nodes
# Ready, control-plane and CloudNativePG operator pods ready). Before a drain, the script reports the factors that distorted the first
# measurement (DiskPressure on the nodes, whether the images are listed on the other nodes) so they can be
# fixed or accepted first.
#
# Exits 0 when the login probe stayed within --target (or no target was given), 2 when it exceeded it, 1 on
# any other failure, including a drain that failed or did not finish (the result is then not a valid drain
# measurement, although the report is still written). Manual only (disrupts the cluster, needs a kubecontext and network access to Keycloak).
#
# Usage: scripts/keycloak-drain-drill.sh -e <env> [--node <node>] [--observe] [--target <seconds>]
#                                        [--interval <seconds>] [--timeout <seconds>]
#                                        [--drain-timeout <seconds>] [--out <dir>] [--yes]
set -eu

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

NAMESPACE="keycloak"
KEYCLOAK_POD="keycloak-0"
DB_CLUSTER="keycloak-db"
CNPG_NAMESPACE="cnpg-system"
# Consecutive healthy samples that count as recovered, and the time after the end of a drain within which a
# drill without any outage is accepted as "the drain did not touch Keycloak".
STABLE_SAMPLES=5
GRACE_SECONDS=60
BASELINE_SECONDS=10
# How long to keep retrying kubectl while the API server is unreachable: for the final uncordon, and for
# collecting events and pods after the measurement.
UNCORDON_WAIT=300
DATA_WAIT=300

# Prints the synopsis and exits non-zero.
usage() {
    echo "Usage: $(basename "$0") -e <env> [--node <node>] [--observe] [--target <seconds>] [--interval <seconds>] [--timeout <seconds>] [--drain-timeout <seconds>] [--out <dir>] [--yes]" >&2
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

# Runs kc with the arguments after $1, retrying every 10 s for up to $1 seconds: the API server of the
# environment can be unreachable for minutes during a drill. Returns non-zero if it never succeeded.
kc_retry() {
    wait_seconds="$1"
    shift
    deadline=$(($(now) + wait_seconds))
    until kc "$@"; do
        if [ "$(now)" -ge "${deadline}" ]; then
            return 1
        fi
        sleep 10
    done
}

# Exits 0 while the background drain is still running.
drain_running() {
    [ -n "${DRAIN_PID}" ] && kill -0 "${DRAIN_PID}" 2>/dev/null
}

# Once the background drain has ended, records its exit status, end time and duration and logs the outcome. A
# failed drain does not stop the measurement: the pods it already evicted still have to come back.
reap_drain() {
    [ -n "${DRAIN_PID}" ] || return 0
    if drain_running; then
        return 0
    fi
    DRAIN_STATUS=0
    wait "${DRAIN_PID}" || DRAIN_STATUS=$?
    DRAIN_PID=""
    DRAIN_END=$(now)
    DRAIN_SECONDS=$((DRAIN_END - T0))
    if [ "${DRAIN_STATUS}" -eq 0 ]; then
        log info "drain returned" "seconds" "${DRAIN_SECONDS}"
    else
        log error "kubectl drain failed, the measurement continues (see ${OUT}/drain.txt)" "seconds" "${DRAIN_SECONDS}" "exit" "${DRAIN_STATUS}"
    fi
}

# Stops a drain that is still running (timeout or Ctrl-C), so it does not keep evicting pods unobserved.
stop_drain() {
    if drain_running; then
        kill "${DRAIN_PID}" 2>/dev/null || true
        wait "${DRAIN_PID}" 2>/dev/null || true
    fi
}

# Uncordons the node if this run cordoned it, retrying while the API server is unreachable.
uncordon_node() {
    if [ "${CORDONED}" -eq 1 ]; then
        if kc_retry "${UNCORDON_WAIT}" uncordon "${NODE}" >/dev/null 2>&1; then
            log info "node uncordoned" "node" "${NODE}"
            CORDONED=0
        else
            log error "could not uncordon, do it by hand" "node" "${NODE}"
        fi
    fi
}

# Stops the drain and the probes and, if this run cordoned a node, uncordons it again. Runs on every exit, so a
# Ctrl-C in the middle of a drain does not leave the node unschedulable.
cleanup() {
    stop_drain
    for pid in ${PROBE_PIDS}; do
        kill "${pid}" 2>/dev/null || true
    done
    PROBE_PIDS=""
    uncordon_node
}

# Exits fatal unless the control plane is healthy enough to take a drill: the API server answers /readyz, every
# node is Ready, the kube-apiserver/-controller-manager/-scheduler pods are ready and so are the pods of the
# CloudNativePG operator, which has to recreate the database pod after the eviction. A drill on a wobbling
# control plane measures the control plane, not Keycloak (see docs/keycloak-drain-drill.md).
control_plane_check() {
    if ! kc get --raw /readyz --request-timeout=10s >/dev/null 2>&1; then
        log fatal "the API server is not ready, not starting the drill"
        exit 1
    fi
    unhealthy=$(
        kc get nodes -o json | jq -r '.items[] | select(first(.status.conditions[] | select(.type == "Ready") | .status) != "True") | "node/\(.metadata.name)"'
        kc -n kube-system get pods -o json | jq -r '.items[] | select(.metadata.name | test("^kube-(apiserver|controller-manager|scheduler)-")) | select((.status.containerStatuses // []) | (length == 0 or any(.[]; .ready | not))) | "pod/kube-system/\(.metadata.name)"'
        kc -n "${CNPG_NAMESPACE}" get pods -o json | jq -r '.items[] | select(.status.phase == "Running") | select((.status.containerStatuses // []) | any(.[]; .ready | not)) | "pod/'"${CNPG_NAMESPACE}"'/\(.metadata.name)"'
    )
    if [ -n "${unhealthy}" ]; then
        log fatal "the control plane is not healthy, not starting the drill" "not ready" "$(printf '%s' "${unhealthy}" | paste -sd ' ' -)"
        exit 1
    fi
}

# Runs one probe in a loop until killed, appending "<epoch>\t<http status>" to $OUT/<name>.tsv per sample:
# $1 name, $2 HTTP method, $3 URL, optional $4 form body, optional $5 a string the response body must contain.
# Status 000 means curl got no answer within 3 s. A status whose body lacks $5 is recorded as "<status>-body",
# because the status alone is ambiguous (a 400 also covers malformed requests, an error page has no JSON).
probe_loop() {
    body="${OUT}/$1.body"
    while true; do
        rm -f "${body}"
        if [ -n "${4:-}" ]; then
            code=$(curl -s -o "${body}" -w '%{http_code}' --max-time 3 -X "$2" --data "$4" "$3" 2>/dev/null) || true
        else
            code=$(curl -s -o "${body}" -w '%{http_code}' --max-time 3 -X "$2" "$3" 2>/dev/null) || true
        fi
        code="${code:-000}"
        if [ -n "${5:-}" ] && [ "${code}" != "000" ] && ! grep -q -- "$5" "${body}" 2>/dev/null; then
            code="${code}-body"
        fi
        printf '%s\t%s\n' "$(now)" "${code}" >>"${OUT}/$1.tsv"
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
    if [ "${OBSERVE}" -eq 0 ]; then
        if [ "${DRAIN_STATUS:-}" = "0" ]; then
            echo "kubectl drain finished after ${DRAIN_SECONDS}s"
        elif [ -n "${DRAIN_STATUS:-}" ]; then
            echo "kubectl drain FAILED after ${DRAIN_SECONDS}s (exit ${DRAIN_STATUS}, see drain.txt): the node was only partly drained"
        else
            echo "kubectl drain did not finish within the measurement and was stopped"
        fi
    fi
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
DRAIN_TIMEOUT=900
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
        --drain-timeout)
            DRAIN_TIMEOUT="$2"
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
DRAIN_PID=""
DRAIN_END=""
DRAIN_STATUS=""
DRAIN_SECONDS=""
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

control_plane_check
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
probe_loop login POST "${TOKEN_URL}" "client_id=admin-cli&grant_type=password&username=drill-probe-no-such-user&password=drill-probe" invalid_grant &
PROBE_PIDS="${PROBE_PIDS} $!"

log info "recording a healthy baseline" "seconds" "${BASELINE_SECONDS}" "url" "${BASE_URL}"
sleep "${BASELINE_SECONDS}"
if ! probe_healthy discovery 200 || ! probe_healthy login 400; then
    log fatal "the probes are not healthy before the drill, nothing meaningful to measure (see ${OUT})" "discovery" "$(tail -n 1 "${OUT}/discovery.tsv")" "login" "$(tail -n 1 "${OUT}/login.tsv")"
    exit 1
fi

T0=$(now)
if [ "${OBSERVE}" -eq 0 ]; then
    log info "draining node" "node" "${NODE}" "drain timeout" "${DRAIN_TIMEOUT}s"
    CORDONED=1
    # kubectl directly, not via kc(): a backgrounded function would leave kubectl running when it is killed
    kubectl --context "${CTX}" drain "${NODE}" --ignore-daemonsets --delete-emptydir-data --timeout="${DRAIN_TIMEOUT}s" >"${OUT}/drain.txt" 2>&1 &
    DRAIN_PID=$!
else
    log info "measuring now: disturb the node (drain, reboot, stop the VM), the script ends once the outage is over" "node" "${NODE}"
fi

while true; do
    reap_drain
    elapsed=$(($(now) - T0))
    if [ "${elapsed}" -gt "${TIMEOUT}" ]; then
        log error "timed out before the drain ended and the probes recovered" "seconds" "${elapsed}"
        break
    fi
    if [ -z "${DRAIN_PID}" ] && probe_healthy discovery 200 && probe_healthy login 400; then
        if probe_failed_once discovery 200 || probe_failed_once login 400; then
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

stop_drain
for pid in ${PROBE_PIDS}; do kill "${pid}" 2>/dev/null || true; done
PROBE_PIDS=""
uncordon_node

for kind in events pods; do
    kc_retry "${DATA_WAIT}" -n "${NAMESPACE}" get "${kind}" -o json >"${OUT}/${kind}.json" 2>/dev/null || {
        log error "could not collect ${kind}, the timeline will lack them" "namespace" "${NAMESPACE}"
        echo '{"items":[]}' >"${OUT}/${kind}.json"
    }
done
analyze_probe discovery 200 >"${OUT}/discovery.summary.json"
analyze_probe login 400 >"${OUT}/login.summary.json"

report | tee "${OUT}/report.txt"
# report runs in a pipeline subshell, so its LOGIN_TOTAL is gone here
LOGIN_TOTAL=$(jq -r .total "${OUT}/login.summary.json")
log info "data kept" "dir" "${OUT}"

if [ "${OBSERVE}" -eq 0 ] && [ "${DRAIN_STATUS}" != "0" ]; then
    log error "the drain failed or did not finish: not a valid drain measurement" "dir" "${OUT}"
    exit 1
fi
if [ -n "${TARGET}" ] && [ "${LOGIN_TOTAL}" -gt "${TARGET}" ]; then
    exit 2
fi
