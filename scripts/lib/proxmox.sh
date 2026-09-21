# shellcheck shell=bash
# Shared helpers for the scripts/proxmox-vm-*.sh scripts (#1296): Proxmox REST API auth, VM discovery, task
# polling. Bash only (unlike scripts/lib/common.sh, which both `sh` and `bash` callers source) -- the
# snapshot script needs bash arrays for its parallel-VM PID tracking, so every proxmox-vm-*.sh script is
# bash throughout rather than mixing shells.
#
# Usage (from a script living directly under scripts/, after sourcing lib/common.sh):
#   . "${SCRIPTS_DIR}/lib/proxmox.sh"

# Every mktemp'd curl-config file created by proxmox_curl (see below) is appended here so the EXIT trap
# below can remove them all on exit. Each process (the main script, and each of its backgrounded parallel
# subshells) gets its own copy of this array via bash's normal fork semantics, and its own copy of this
# trap -- so a temp file created inside a backgrounded snapshot_one/rollback_one call is cleaned up by that
# subshell's own exit, not leaked waiting for the parent.
PROXMOX_CLEANUP_FILES=()
proxmox_cleanup() {
    local f
    for f in "${PROXMOX_CLEANUP_FILES[@]:-}"; do
        [ -n "${f}" ] && rm -f "${f}"
    done
}
trap proxmox_cleanup EXIT

# Decrypts terragrunt/global-secrets.sops.yaml in-memory (sops -d output only ever lives in a shell
# variable, never written to disk) and populates PROXMOX_ENDPOINT / PROXMOX_INSECURE / PROXMOX_API_TOKEN.
# Reuses the exact same token Terraform already uses to create/destroy these VMs
# (terragrunt/_envcommon/vehagn-k8s.hcl) -- already trusted with strictly more power than snapshot/rollback
# needs, so this doesn't introduce a new credential or trust boundary.
proxmox_load_secrets() {
    local secrets_file="${REPO_ROOT}/terragrunt/global-secrets.sops.yaml"
    local secrets_yaml
    secrets_yaml=$(sops -d "${secrets_file}") || {
        log fatal "failed to decrypt secrets file via sops" "file" "${secrets_file}"
        exit 1
    }

    PROXMOX_ENDPOINT=$(yq -r '.proxmox.endpoint // ""' <<<"${secrets_yaml}")
    PROXMOX_INSECURE=$(yq -r '.proxmox.insecure // false' <<<"${secrets_yaml}")
    PROXMOX_API_TOKEN=$(yq -r '.proxmox_api_token // ""' <<<"${secrets_yaml}")

    if [ -z "${PROXMOX_ENDPOINT}" ] || [ -z "${PROXMOX_API_TOKEN}" ]; then
        log fatal "terragrunt/global-secrets.sops.yaml is missing proxmox.endpoint or proxmox_api_token"
        exit 1
    fi
}

# Issues one Proxmox API call: <method> is GET/POST/DELETE, <path> starts with / (e.g.
# "/cluster/resources?type=vm"), and any further arguments are form-urlencoded POST/query fields (e.g.
# "snapname=initial"). Prints the response body's .data field (jq) to stdout; returns non-zero (having
# already logged the response) on a non-2xx HTTP status or curl failure.
#
# The API token is passed to curl via a chmod 600 --config file (`header = "Authorization: ..."`), not a
# plain -H flag -- the latter's value is visible to other local users via `ps`, the former isn't. One config
# file per call, cleaned up via PROXMOX_CLEANUP_FILES/the EXIT trap above rather than immediately after use,
# so it survives exactly as long as the curl invocation that needs it and no longer.
proxmox_curl() {
    local method="$1" path="$2"
    shift 2

    local cfg
    cfg=$(mktemp)
    PROXMOX_CLEANUP_FILES+=("${cfg}")
    chmod 600 "${cfg}"
    printf 'header = "Authorization: PVEAPIToken=%s"\n' "${PROXMOX_API_TOKEN}" >"${cfg}"

    local curl_args=(--config "${cfg}" -sS -X "${method}" --write-out '\n%{http_code}')
    # Only skip TLS verification when the secret itself says to -- fail-closed by default, the same trust
    # decision the bpg/proxmox Terraform provider already encodes for this same token/endpoint pair.
    [ "${PROXMOX_INSECURE}" = "true" ] && curl_args+=(--insecure)

    local field
    for field in "$@"; do
        curl_args+=(--data-urlencode "${field}")
    done
    # -d/--data-urlencode otherwise forces POST; -G keeps a GET a GET, turning any fields into a query string.
    [ "${method}" = "GET" ] && [ "$#" -gt 0 ] && curl_args+=(-G)

    local response http_code body
    response=$(curl "${curl_args[@]}" "${PROXMOX_ENDPOINT}/api2/json${path}") || {
        log error "curl failed calling the Proxmox API" "method" "${method}" "path" "${path}"
        return 1
    }
    http_code="${response##*$'\n'}"
    body="${response%$'\n'*}"

    if [ "${http_code}" -lt 200 ] || [ "${http_code}" -ge 300 ]; then
        log error "Proxmox API call failed" "method" "${method}" "path" "${path}" "http_code" "${http_code}" "body" "${body}"
        return 1
    fi

    jq -r '.data' <<<"${body}"
}

# Maps an environment name to its single-digit Proxmox ID, per docs/architecture/environments.md's
# "Environment ID" table -- the same not-centralized precedent as that doc's other consumer, the per-env
# `localASN: 6452<id>` hardcoded into each k8s/infra/kube-system/cilium/envs/<env>/bgp-cluster-config.yaml.
# Keep this in sync with that table if it's ever renumbered.
proxmox_env_id() {
    case "$1" in
        head) echo 1 ;;
        qa) echo 2 ;;
        dev) echo 3 ;;
        src) echo 5 ;;
        poc) echo 6 ;;
        rebuild) echo 7 ;;
        prod) echo 8 ;;
        dbg) echo 9 ;;
        *)
            log fatal "no known Proxmox environment ID for this environment -- update proxmox_env_id() in scripts/lib/proxmox.sh (see docs/architecture/environments.md)" "env" "$1"
            exit 1
            ;;
    esac
}

# Prints "<vmid>\t<node>\t<name>\t<status>" for every QEMU VM belonging to <env>, sorted by vmid ascending
# (which also puts control-plane nodes, vmid suffix 1-3, before workers, suffix 4+ -- see
# docs/architecture/environments.md). A VM is only included if BOTH its vmid matches the documented
# 70081<id><n> scheme AND its name starts with "<env>-" -- defense in depth, so a stale id mapping or a
# vmid collision can't silently include another environment's VM. A vmid match without the name match is
# logged and excluded rather than trusted.
proxmox_discover_vms() {
    local env="$1" id
    id=$(proxmox_env_id "${env}")

    local resources
    resources=$(proxmox_curl GET "/cluster/resources?type=vm") || {
        log fatal "failed to list Proxmox cluster resources"
        exit 1
    }

    local vmid node name status
    while IFS=$'\t' read -r vmid node name status; do
        [ -z "${vmid}" ] && continue
        if [[ ! "${vmid}" =~ ^70081${id}[0-9]$ ]]; then
            continue
        fi
        case "${name}" in
            "${env}-"*) ;;
            *)
                log warn "VM matches ${env}'s vmid pattern but not its name prefix -- excluding" "vmid" "${vmid}" "name" "${name}"
                continue
                ;;
        esac
        printf '%s\t%s\t%s\t%s\n' "${vmid}" "${node}" "${name}" "${status}"
    done < <(jq -r '.[] | select(.type=="qemu") | [.vmid, .node, .name, .status] | @tsv' <<<"${resources}" | sort -n)
}

# Polls a Proxmox task (a UPID returned by an async API call like snapshot creation/rollback/start/stop)
# every 3s up to a 10 minute cap, same polling shape as scripts/kopiur-create.sh's backup_one(). Returns 0
# only once the task's exitstatus is exactly "OK"; logs the task's own log tail on failure or timeout.
proxmox_wait_task() {
    local node="$1" upid="$2"
    local status_json task_status exitstatus i

    for i in $(seq 1 200); do
        status_json=$(proxmox_curl GET "/nodes/${node}/tasks/${upid}/status") || return 1
        task_status=$(jq -r '.status' <<<"${status_json}")
        [ "${task_status}" != "running" ] && break
        sleep 3
    done

    if [ "${task_status}" = "running" ]; then
        log error "timed out waiting for Proxmox task" "node" "${node}" "upid" "${upid}"
        return 1
    fi

    exitstatus=$(jq -r '.exitstatus // "unknown"' <<<"${status_json}")
    if [ "${exitstatus}" != "OK" ]; then
        log error "Proxmox task failed" "node" "${node}" "upid" "${upid}" "exitstatus" "${exitstatus}"
        local task_log
        task_log=$(proxmox_curl GET "/nodes/${node}/tasks/${upid}/log" 2>/dev/null || true)
        [ -n "${task_log}" ] && log_debug_output "$(jq -r '.[].t' <<<"${task_log}" 2>/dev/null)"
        return 1
    fi
}

# Validates a snapshot name against Proxmox's own pve-configid-style constraint (the same shape as an
# existing Proxmox id in this repo, e.g. the "local-enc" storage id: starts with a letter/digit/underscore,
# followed by letters/digits/underscores/hyphens), plus an explicit rejection of "current" (Proxmox's
# reserved name for the live/uncommitted VM state, never a real snapshot). This mirrors, but doesn't
# replace, Proxmox's own server-side validation -- verify empirically against a real cluster before relying
# on it (see docs/proxmox-vm-snapshots.md).
proxmox_validate_snapshot_name() {
    local name="$1"
    if [ "${name}" = "current" ]; then
        log fatal "'current' is reserved by Proxmox for the live VM state -- pick a different --name"
        exit 1
    fi
    if [[ ! "${name}" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_-]*$ ]]; then
        log fatal "invalid snapshot name -- must start with a letter/digit/underscore, followed by letters/digits/underscores/hyphens" "name" "${name}"
        exit 1
    fi
}
