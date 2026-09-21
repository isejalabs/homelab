#!/usr/bin/env -S just --justfile

set minimum-version := '1.55.0'

set default-list
set default-script
set lazy
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

# Bootstrap cluster CRDs and apps
mod bootstrap "k8s/bootstrap"

# App backup/restore maintenance recipes
mod backup "scripts/backup.just"

# Proxmox VM snapshot/rollback recipes (#1296)
mod proxmox "scripts/proxmox.just"

[private]
logstep stage msg:
    just log debug "Running step... {{msg}}" "stage" "{{ stage }}"

[private]
log lvl msg *args:
    # `--` stops gum's own flag parsing before msg/args, so a message that happens to start with a dash
    # (e.g. "-e/--environment must be one of...") isn't misread as a gum flag - see #1275.
    gum log -t rfc3339 -s -l "{{ lvl }}" -- "{{ msg }}" {{ args }}

[private]
template file *args:
    minijinja-cli "{{ file }}" {{ args }} | op inject
