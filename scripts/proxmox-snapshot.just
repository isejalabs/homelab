set default-list
set default-script
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[doc('Create a Proxmox snapshot on every VM in an environment, in one go, via the Proxmox API (-e/--environment required; --name defaults to "initial")')]
[arg('environment', short='e', long='environment')]
[arg('name', long='name')]
create environment name="initial":
    "{{ justfile_directory() }}/scripts/proxmox-snapshot-create.sh" -e {{ environment }} --name {{ name }}

[doc('List the Proxmox VMs of an environment and their snapshots via the Proxmox API (-e/--environment required)')]
[arg('environment', short='e', long='environment')]
list environment:
    "{{ justfile_directory() }}/scripts/proxmox-snapshot-list.sh" -e {{ environment }}

[doc('Delete a named snapshot from every VM in an environment, or just one with --vmid, via the Proxmox API (-e/--environment required; --name defaults to "initial"; destructive -- prompts for confirmation unless --yes or --vmid is given)')]
[arg('environment', short='e', long='environment')]
[arg('name', long='name')]
[arg('vmid', long='vmid')]
[arg('yes', short='y', long='yes', value='true')]
delete environment name="initial" vmid="" yes="false":
    "{{ justfile_directory() }}/scripts/proxmox-snapshot-delete.sh" -e {{ environment }} --name {{ name }} \
        {{ if vmid != "" { "--vmid " + vmid } else { "" } }} \
        {{ if yes == "true" { "--yes" } else { "" } }}

[doc('Roll back every VM in an environment to a named snapshot and restart them, in one go, via the Proxmox API (-e/--environment required; --name defaults to "initial"; destructive -- prompts for confirmation unless --yes)')]
[arg('environment', short='e', long='environment')]
[arg('name', long='name')]
[arg('yes', short='y', long='yes', value='true')]
[arg('no_start', long='no-start', value='true')]
rollback environment name="initial" yes="false" no_start="false":
    "{{ justfile_directory() }}/scripts/proxmox-snapshot-rollback.sh" -e {{ environment }} --name {{ name }} \
        {{ if yes == "true" { "--yes" } else { "" } }} \
        {{ if no_start == "true" { "--no-start" } else { "" } }}
