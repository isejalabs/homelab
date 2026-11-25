set default-list
set default-script
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

# `default-list` above only lists recipes when truly no arguments are given -- e.g. `just proxmox::snapshot
# -e dev` (action omitted, but a flag given) still has just pick the first recipe below as the default and
# fail on its required arg instead. This catch-all absorbs any such leftover arguments and lists recipes
# instead, so an omitted action behaves the same regardless of what else was typed.
[private]
default *args:
    {{ just_executable() }} --justfile {{ source_file() }} --list

[arg('environment', long='environment', short='e')]
[arg('name', long='name')]
[doc('Create a Proxmox snapshot on every VM in an environment, in one go, via the Proxmox API (-e/--environment required; --name defaults to "initial")')]
create environment name="initial":
    "{{ justfile_directory() }}/scripts/ops/proxmox/snapshot-create.sh" -e {{ environment }} --name {{ name }}

[arg('environment', long='environment', short='e')]
[doc('List the Proxmox VMs of an environment and their snapshots via the Proxmox API (-e/--environment required)')]
list environment:
    "{{ justfile_directory() }}/scripts/ops/proxmox/snapshot-list.sh" -e {{ environment }}

[arg('environment', long='environment', short='e')]
[arg('name', long='name')]
[arg('vmid', long='vmid')]
[arg('yes', long='yes', short='y', value='true')]
[doc('Delete a named snapshot from every VM in an environment, or just one with --vmid, via the Proxmox API (-e/--environment required; --name defaults to "initial"; destructive -- prompts for confirmation unless --yes or --vmid is given)')]
delete environment name="initial" vmid="" yes="false":
    "{{ justfile_directory() }}/scripts/ops/proxmox/snapshot-delete.sh" -e {{ environment }} --name {{ name }} \
        {{ if vmid != "" { "--vmid " + vmid } else { "" } }} \
        {{ if yes == "true" { "--yes" } else { "" } }}

[arg('environment', long='environment', short='e')]
[arg('name', long='name')]
[arg('no_start', long='no-start', value='true')]
[arg('yes', long='yes', short='y', value='true')]
[doc('Roll back every VM in an environment to a named snapshot and restart them, in one go, via the Proxmox API (-e/--environment required; --name defaults to "initial"; destructive -- prompts for confirmation unless --yes)')]
rollback environment name="initial" yes="false" no_start="false":
    "{{ justfile_directory() }}/scripts/ops/proxmox/snapshot-rollback.sh" -e {{ environment }} --name {{ name }} \
        {{ if yes == "true" { "--yes" } else { "" } }} \
        {{ if no_start == "true" { "--no-start" } else { "" } }}
