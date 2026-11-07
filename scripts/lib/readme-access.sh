# shellcheck shell=sh
# Helpers for check-unit-readme-hostnames.sh: which hostnames a unit README's "Access" section links, and which
# environment a hostname belongs to. Sourced, not executed directly, and POSIX `sh` only. Needs lib/flux-sets.sh
# sourced first (flux_envs) and ROOT set.

# The real domain of the clusters; the hostname scheme itself is described in docs/reference/environments.md.
README_DOMAIN="iseja.net"

# Prints the host of every Markdown link target `](http(s)://host...)` in the "Access" section of the README $1, one
# per line, without scheme, userinfo-free path, port or query. Fenced code blocks are skipped and so are URLs that are
# not link targets (a URL in a code span or in prose is not a clickable link, which check-unit-readmes.sh bans in
# "Access" anyway). A <placeholder> host is skipped: it is a template, not a hostname.
readme_access_hosts() {
    awk '
        BEGIN { fence = 0 }
        {
            line = $0
            if (fence == 0 && match(line, /^`+/) && RLENGTH >= 3) { fence = RLENGTH; next }
            if (fence > 0) {
                if (match(line, /^`+[ \t]*$/) && RLENGTH >= fence) fence = 0
                next
            }
            if (line ~ /^## /) { sec = substr(line, 4); sub(/[ \t]+$/, "", sec) }
            if (sec != "Access") next
            while (match(line, /\]\(https?:\/\/[^) \t]*\)/)) {
                print substr(line, RSTART + 2, RLENGTH - 3)
                line = substr(line, RSTART + RLENGTH)
            }
        }' "$1" |
        sed -E 's#^https?://##; s#[/:?\#].*$##' |
        grep -v '[<>]' || true
}

# Prints the environment a hostname belongs to, nothing if it fits no scheme. The schemes are `<env>-<sub>.<env>.iseja.net`
# for every environment but prod, `<sub>.prod.iseja.net` for prod (no prefix), and `<sub>.iseja.net` for the one prod
# exception, Keycloak's `auth.iseja.net` (set in k8s/apps/identity/keycloak/envs/prod/kustomization.yaml). Known
# environments are the directories under flux/envs.
readme_host_env() {
    zone=${1%".${README_DOMAIN}"}
    [ "${zone}" != "$1" ] || return 0
    case "${zone}" in
    *.*.*) return 0 ;;
    *.*)
        label=${zone%%.*}
        env=${zone#*.}
        ;;
    *)
        echo prod
        return 0
        ;;
    esac
    flux_envs | grep -qFx "${env}" || return 0
    if [ "${env}" != prod ]; then
        case "${label}" in
        "${env}-"?*) ;;
        *) return 0 ;;
        esac
    fi
    echo "${env}"
}
