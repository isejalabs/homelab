#!/bin/sh
# Unit test of the disclosure guard (the disclosure-* hooks in .pre-commit-config.yaml and
# scripts/tools/check-private-terms.sh): in a throwaway git repository it seeds one violation per pattern class
# and expects the matching hook to fail, then seeds values the allowlists must let through and expects a pass.
# Every seeded value is synthetic: a reserved or unallocated address, a never-delegated top-level domain, a
# locally administered MAC. They are assembled from parts so this file itself passes the guard it tests, and
# nothing here is, or may become, a real string. Runs in the pre-commit workflow next to the hooks.
#
# Usage: scripts/ci/test-disclosure-hooks.sh     (from anywhere; needs pre-commit and git)

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
CONFIG="${ROOT}/.pre-commit-config.yaml"
# The scratch repository lives under the repo root so that mise (which resolves the pre-commit version from
# .mise.toml) and its trust settings apply to it; the .gitignore-free name is removed again on exit.
WORK=$(mktemp -d "${ROOT}/.disclosure-test.XXXXXX")
trap 'rm -rf "${WORK}"' EXIT
FAILED=0

# Fails the test run with a message when a check did not behave as expected.
fail() {
    echo "FAIL: $1" >&2
    FAILED=1
}

# Runs one hook on one file in the throwaway repository; returns pre-commit's exit status (0 passed, 1 a hook
# failed, anything else is an error of pre-commit itself, which the callers treat as a test failure). $1 hook
# id, $2 file.
run_hook() {
    (cd "${WORK}/repo" && pre-commit run --config "${CONFIG}" "$1" --files "$2" >/dev/null 2>&1)
}

# Expects hook $1 to flag the file with content $3 (file name $2).
expect_flagged() {
    printf '%s\n' "$3" > "${WORK}/repo/$2"
    rc=0
    run_hook "$1" "$2" || rc=$?
    if [ "${rc}" -eq 1 ]; then echo "ok: $1 flags $2"; else fail "$1 on its seeded violation ($2) exited ${rc}, expected 1"; fi
}

# Expects hook $1 to let the file with content $3 (file name $2) through.
expect_clean() {
    printf '%s\n' "$3" > "${WORK}/repo/$2"
    if run_hook "$1" "$2"; then echo "ok: $1 allows $2"; else fail "$1 flagged an allowed value ($2)"; fi
}

mkdir "${WORK}/repo"
git -C "${WORK}/repo" init -q
mkdir -p "${WORK}/repo/scripts/tools"
cp "${ROOT}/scripts/tools/check-private-terms.sh" "${WORK}/repo/scripts/tools/"

# Synthetic violations, one per class.
EMAIL_BAD="seeded.person@mail""host.corp"
MAC_BAD="02:00:00:aa:""bb:cc"
IP_BAD="198.18.0"".77"
SERIAL_BAD="Serial: ZZTEST""123456"

expect_flagged disclosure-email email.md "contact ${EMAIL_BAD}"
expect_flagged disclosure-mac mac.md "nic ${MAC_BAD}"
expect_flagged disclosure-public-ip ip.md "gateway ${IP_BAD}"
expect_flagged disclosure-serial serial.md "${SERIAL_BAD}"

expect_clean disclosure-email email-ok.md "a@example.com, noreply@host.corp, ssh root@host.corp, bob@dir.local, bob-adm@DIR.EXAMPLE.COM."
expect_clean disclosure-email email-marker.md "${EMAIL_BAD} <!-- disclosure:allow -->"
expect_clean disclosure-mac mac-ok.md "00:00:5E:00:53:01 and AA:BB:CC:DD:EE:FF and 00:00:00:00:00:00"
expect_clean disclosure-public-ip ip-ok.md "10.1.2.3 192.168.1.1 172.20.0.1 203.0.113.7 198.51.100.1 192.0.2.1 100.64.0.1 255.255.255.0 1.1.1.1 8.8.8.8 and v1.2.3"
expect_clean disclosure-public-ip ip-marker.md "${IP_BAD} # disclosure:allow"
expect_clean disclosure-serial serial-ok.md "serial: 1, S/N <number>, Serial number: pending"

# The private term list: flagged with a list, a no-op without one, and the term never reaches the output.
TERM_SYNTH="zzq-synthetic-""term"
printf '# comment\n\n%s\n' "${TERM_SYNTH}" > "${WORK}/terms.txt"
printf 'text with ZZQ-Synthetic-Term inside\n' > "${WORK}/repo/private.md"
printf 'clean\n' > "${WORK}/repo/private-ok.md"
rc=0
out=$(cd "${WORK}/repo" && DISCLOSURE_TERMS_FILE="${WORK}/terms.txt" pre-commit run --config "${CONFIG}" disclosure-private-terms --files private.md 2>&1) || rc=$?
if [ "${rc}" -ne 1 ]; then
    fail "disclosure-private-terms on a listed term exited ${rc}, expected 1"
else
    echo "ok: disclosure-private-terms flags a listed term"
    case "${out}" in *"${TERM_SYNTH}"*) fail "the output repeats a private term" ;; *) echo "ok: the output does not repeat the term" ;; esac
fi
if (cd "${WORK}/repo" && DISCLOSURE_TERMS_FILE="${WORK}/terms.txt" pre-commit run --config "${CONFIG}" disclosure-private-terms --files private-ok.md >/dev/null 2>&1); then
    echo "ok: disclosure-private-terms allows a clean file"
else
    fail "disclosure-private-terms flagged a clean file"
fi
if out=$(cd "${WORK}/repo" && XDG_CONFIG_HOME="${WORK}/no-config-dir" DISCLOSURE_TERMS_FILE="" pre-commit run --config "${CONFIG}" disclosure-private-terms --files private.md 2>&1); then
    case "${out}" in *skipped*) echo "ok: disclosure-private-terms is a no-op with a message when unset" ;; *) fail "no skip message when unset" ;; esac
else
    fail "disclosure-private-terms failed without a configured list"
fi

exit "${FAILED}"
