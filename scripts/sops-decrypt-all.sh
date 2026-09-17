#!/bin/bash
# Decrypts every *.sops.yaml in the repo into its plaintext sibling (<name>.yaml), skipping any file whose
# existing plaintext sibling already matches the decrypted content, so a bulk re-decrypt doesn't needlessly
# touch files an editor/IDE might have open. The counterpart to sops-encrypt-all.sh.
#
# Usage: scripts/sops-decrypt-all.sh [-f|--force]
# Without -f/--force, a plaintext sibling that differs from the decrypted content is left alone (with a
# warning) rather than overwritten, to avoid silently discarding local plaintext edits.

SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPTS_DIR}/lib/common.sh"

force=false

# Parses -f/--force; any other flag is a usage error.
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
    -f | --force)
        force=true
        shift
        ;;
    *)
        just log fatal "unknown option" "flag" "$1"
        exit 1
        ;;
    esac
done

# Finds every *.sops.yaml file in the repo and decrypts each one in turn.
find . -regextype egrep -regex "\.\/.+\/.*.sops.yaml" -type f | while IFS= read -r file; do
    decrypted_file="${file%.sops.yaml}.yaml"

    if [ -f "$decrypted_file" ]; then
        # Decrypt the encrypted version
        decrypted_temp=$(mktemp)
        sops --decrypt "$file" >"$decrypted_temp"

        # Compare the decrypted version with the existing decrypted file
        if cmp -s "$decrypted_file" "$decrypted_temp"; then
            just log info "no changes detected, skipping decryption" "file" "$file"
        else
            if [ "$force" = true ]; then
                mv "$decrypted_temp" "$decrypted_file"
                just log warn "file replaced with decrypted content" "file" "$decrypted_file"
            else
                just log warn "changes detected, use -f/--force to overwrite" "file" "$file"
            fi
        fi

        if [ -f "$decrypted_temp" ]; then
            rm "$decrypted_temp"
        fi
    else
        # No decrypted file exists, decrypt and create it
        just log info "decrypting" "file" "$file"
        sops --decrypt "$file" >"$decrypted_file"
    fi
done
