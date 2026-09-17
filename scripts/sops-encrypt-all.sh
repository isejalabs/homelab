#!/bin/bash
# Re-encrypts every plaintext file matched by a `path_regex:` entry in .sops.yaml into its *.sops.yaml
# sibling, skipping any pair whose existing encrypted sibling already decrypts to matching content, so a
# bulk re-encrypt only touches files that actually changed. The counterpart to sops-decrypt-all.sh.
#
# Usage: scripts/sops-encrypt-all.sh
# Takes no arguments; run from the repo root. Always overwrites a stale *.sops.yaml (no -f/--force gate,
# unlike sops-decrypt-all.sh) since re-encrypting can't lose local plaintext edits the way decrypting can.

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

# Each path_regex from .sops.yaml is used as a find(1) regex to locate the plaintext files it covers. A rule
# written against the encrypted filename (containing a literal ".sops", e.g. matching "*.sops.yaml") has that
# substring stripped so it resolves to the plaintext name instead; a rule already written against the
# plaintext name (e.g. "*-secrets.yaml") passes through unchanged.
while IFS= read -r path; do
    path=${path/.sops/ }
    find . -regextype egrep -regex ".*/$path" -type f | while IFS= read -r file; do
        encrypted_file="${file%.yaml}.sops.yaml"

        if [ -f "$encrypted_file" ]; then
            # Decrypt the encrypted version
            decrypted_temp=$(mktemp)
            sops --decrypt "$encrypted_file" >"$decrypted_temp"

            # Compare the decrypted version with the file on disk
            if cmp -s "$file" "$decrypted_temp"; then
                just log info "no changes detected, skipping encryption" "file" "$file"
            else
                just log info "changes detected, re-encrypting" "file" "$file"
                sops --encrypt "$file" >"$encrypted_file"
            fi

            rm "$decrypted_temp"
        else
            # No encrypted version exists, encrypt the file
            just log info "encrypting (no existing encrypted sibling)" "file" "$file"
            sops --encrypt "$file" >"$encrypted_file"
        fi
    done
done < <(grep -oP '^\s*- path_regex:\s*\K.*' ".sops.yaml")
