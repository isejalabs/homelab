set default-list
set default-script
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[doc('List the Proxmox VMs of an environment and their snapshots via the Proxmox API (-e/--environment required)')]
[arg('environment', short='e', long='environment')]
list environment:
    "{{ justfile_directory() }}/scripts/proxmox-vm-list.sh" -e {{ environment }}

[doc('Create a Proxmox snapshot on every VM in an environment, in one go, via the Proxmox API (-e/--environment required; --name defaults to "initial")')]
[arg('environment', short='e', long='environment')]
[arg('name', long='name')]
snapshot environment name="initial":
    "{{ justfile_directory() }}/scripts/proxmox-vm-snapshot.sh" -e {{ environment }} --name {{ name }}

[doc('Roll back every VM in an environment to a named snapshot and restart them, in one go, via the Proxmox API (-e/--environment required; --name defaults to "initial"; destructive -- prompts for confirmation unless --yes)')]
[arg('environment', short='e', long='environment')]
[arg('name', long='name')]
[arg('yes', short='y', long='yes', value='true')]
[arg('no_start', long='no-start', value='true')]
rollback environment name="initial" yes="false" no_start="false":
    "{{ justfile_directory() }}/scripts/proxmox-vm-rollback.sh" -e {{ environment }} --name {{ name }} \
        {{ if yes == "true" { "--yes" } else { "" } }} \
        {{ if no_start == "true" { "--no-start" } else { "" } }}
