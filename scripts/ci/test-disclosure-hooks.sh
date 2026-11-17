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
RX_SYNTH="zzq-rx-"
printf '# category\tkind(literal|regex)\tterm ; whole-word, case-insensitive\n\nsynthetic\tliteral\t%s\nsynthetic\tregex\t%s[0-9]+\n' "${TERM_SYNTH}" "${RX_SYNTH}" > "${WORK}/terms.tsv"
printf 'text with ZZQ-Synthetic-Term inside\n' > "${WORK}/repo/private.md"
printf 'a code zzq-rx-4711 here\n' > "${WORK}/repo/private-rx.md"
printf 'clean\nsynthetic literal regex\nxzzq-synthetic-termx zzq-rx-\n' > "${WORK}/repo/private-ok.md"
rc=0
out=$(cd "${WORK}/repo" && DISCLOSURE_TERMS_FILE="${WORK}/terms.tsv" pre-commit run --config "${CONFIG}" disclosure-private-terms --files private.md 2>&1) || rc=$?
if [ "${rc}" -ne 1 ]; then
    fail "disclosure-private-terms on a listed term exited ${rc}, expected 1"
else
    echo "ok: disclosure-private-terms flags a listed term"
    # Case-insensitive, because the seeded line spells the term in mixed case.
    case $(printf '%s' "${out}" | tr '[:upper:]' '[:lower:]') in *"${TERM_SYNTH}"*) fail "the output repeats a private term" ;; *) echo "ok: the output does not repeat the term" ;; esac
    # A single file makes grep omit the file name; the output must still be file:line, never the line.
    rc=0
    out=$(DISCLOSURE_TERMS_FILE="${WORK}/terms.tsv" "${ROOT}/scripts/tools/check-private-terms.sh" "${WORK}/repo/private.md" 2>&1) || rc=$?
    case "${rc}:$(printf '%s' "${out}" | tr '[:upper:]' '[:lower:]')" in
        1:*"${TERM_SYNTH}"*) fail "the script prints the matching line for a single file" ;;
        1:*private.md:1:*) echo "ok: a single file reports file:line without the line" ;;
        *) fail "the script on a single file exited ${rc} with unexpected output" ;;
    esac
fi
rc=0
(cd "${WORK}/repo" && DISCLOSURE_TERMS_FILE="${WORK}/terms.tsv" pre-commit run --config "${CONFIG}" disclosure-private-terms --files private-rx.md >/dev/null 2>&1) || rc=$?
if [ "${rc}" -eq 1 ]; then echo "ok: disclosure-private-terms flags a regex entry"; else fail "a regex entry exited ${rc}, expected 1"; fi
if (cd "${WORK}/repo" && DISCLOSURE_TERMS_FILE="${WORK}/terms.tsv" pre-commit run --config "${CONFIG}" disclosure-private-terms --files private-ok.md >/dev/null 2>&1); then
    echo "ok: disclosure-private-terms allows a clean file (category and kind labels, a term inside a longer word, a partial regex match)"
else
    fail "disclosure-private-terms flagged a clean file"
fi
if out=$(cd "${WORK}/repo" && XDG_CONFIG_HOME="${WORK}/no-config-dir" DISCLOSURE_TERMS_FILE="" pre-commit run --config "${CONFIG}" disclosure-private-terms --files private.md 2>&1); then
    case "${out}" in *skipped*) echo "ok: disclosure-private-terms is a no-op with a message when unset" ;; *) fail "no skip message when unset" ;; esac
else
    fail "disclosure-private-terms failed without a configured list"
fi

# The PreToolUse hook that stops a command from publishing a listed term (scripts/agent/disclosure-pre-publish.py).
PRE_PUBLISH="${ROOT}/scripts/agent/disclosure-pre-publish.py"
printf 'body with %s\n' "${TERM_SYNTH}" > "${WORK}/body-bad.md"
printf 'a clean body\n' > "${WORK}/body-ok.md"

# Feeds one Bash command to the hook as a PreToolUse event; sets rc and out. $1 the command, $2 "list" or "nolist".
run_pre_publish() {
    event=$(python3 -I -c 'import json, sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))' "$1")
    rc=0
    if [ "$2" = "list" ]; then
        out=$(printf '%s' "${event}" | DISCLOSURE_TERMS_FILE="${WORK}/terms.tsv" python3 "${PRE_PUBLISH}" 2>&1) || rc=$?
    else
        out=$(printf '%s' "${event}" | XDG_CONFIG_HOME="${WORK}/no-config-dir" DISCLOSURE_TERMS_FILE="" python3 "${PRE_PUBLISH}" 2>&1) || rc=$?
    fi
}

# Expects the hook to exit $1 for command $3 (list mode $2) and its output never to repeat the term. $4 labels the case.
expect_pre_publish() {
    run_pre_publish "$3" "$2"
    if [ "${rc}" -ne "$1" ]; then
        fail "pre-publish hook: $4 exited ${rc}, expected $1"
        return
    fi
    case $(printf '%s' "${out}" | tr '[:upper:]' '[:lower:]') in
        *"${TERM_SYNTH}"*) fail "pre-publish hook: $4 repeats the term" ;;
        *) echo "ok: pre-publish hook $4" ;;
    esac
}

expect_pre_publish 2 list "git commit -m 'fix: about ${TERM_SYNTH}'" "blocks a git commit message with a listed term"
expect_pre_publish 2 list "gh issue create --title t --body \"\$(cat <<'EOF'
text ${TERM_SYNTH}
EOF
)\"" "blocks a heredoc issue body with a listed term"
expect_pre_publish 2 list "gh pr create --body-file ${WORK}/body-bad.md" "blocks a --body-file that contains a listed term"
expect_pre_publish 2 list "git commit -F ${WORK}/body-bad.md" "blocks a git commit -F file that contains a listed term"
expect_pre_publish 2 list "gh release create v1 --notes-file ${WORK}/body-bad.md" "blocks a release --notes-file that contains a listed term"
expect_pre_publish 0 list "gh pr create --body-file ${WORK}/body-ok.md" "allows a clean --body-file"
expect_pre_publish 0 list "git commit -m 'fix: clean message'" "allows a clean commit message"
expect_pre_publish 0 list "echo ${TERM_SYNTH} | wc -c" "ignores a command that publishes nothing"
expect_pre_publish 0 list "gh issue view 1" "ignores a read-only gh command"
expect_pre_publish 0 nolist "git commit -m 'fix: about ${TERM_SYNTH}'" "is a no-op without a private list"

exit "${FAILED}"
