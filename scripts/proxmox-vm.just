set default-list
set default-script
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

# `default-list` above only lists recipes when truly no arguments are given -- e.g. `just proxmox::vm
# -e dev` (action omitted, but a flag given) still has just pick the first recipe below as the default and
# fail on its required arg instead. This catch-all absorbs any such leftover arguments and lists recipes
# instead, so an omitted action behaves the same regardless of what else was typed.
[private]
default *args:
    {{ just_executable() }} --justfile {{ source_file() }} --list

[doc('List the Proxmox VMs of an environment via the Proxmox API (-e/--environment required)')]
[arg('environment', short='e', long='environment')]
list environment:
    "{{ justfile_directory() }}/scripts/proxmox-vm-list.sh" -e {{ environment }}

[doc('Start every VM in an environment, or just one with --vmid, via the Proxmox API (-e/--environment required; safe, never prompts)')]
[arg('environment', short='e', long='environment')]
[arg('vmid', long='vmid')]
start environment vmid="":
    "{{ justfile_directory() }}/scripts/proxmox-vm-power.sh" --action start -e {{ environment }} \
        {{ if vmid != "" { "--vmid " + vmid } else { "" } }}

[doc('Gracefully shut down every VM in an environment, or just one with --vmid, via the Proxmox API (-e/--environment required; destructive -- prompts for confirmation unless --yes or --vmid is given)')]
[arg('environment', short='e', long='environment')]
[arg('vmid', long='vmid')]
[arg('yes', short='y', long='yes', value='true')]
shutdown environment vmid="" yes="false":
    "{{ justfile_directory() }}/scripts/proxmox-vm-power.sh" --action shutdown -e {{ environment }} \
        {{ if vmid != "" { "--vmid " + vmid } else { "" } }} \
        {{ if yes == "true" { "--yes" } else { "" } }}

[doc('Hard-stop every VM in an environment, or just one with --vmid, via the Proxmox API (-e/--environment required; destructive -- prompts for confirmation unless --yes or --vmid is given)')]
[arg('environment', short='e', long='environment')]
[arg('vmid', long='vmid')]
[arg('yes', short='y', long='yes', value='true')]
stop environment vmid="" yes="false":
    "{{ justfile_directory() }}/scripts/proxmox-vm-power.sh" --action stop -e {{ environment }} \
        {{ if vmid != "" { "--vmid " + vmid } else { "" } }} \
        {{ if yes == "true" { "--yes" } else { "" } }}

[doc('Hard-reset every VM in an environment, or just one with --vmid, via the Proxmox API (-e/--environment required; destructive -- prompts for confirmation unless --yes or --vmid is given)')]
[arg('environment', short='e', long='environment')]
[arg('vmid', long='vmid')]
[arg('yes', short='y', long='yes', value='true')]
reset environment vmid="" yes="false":
    "{{ justfile_directory() }}/scripts/proxmox-vm-power.sh" --action reset -e {{ environment }} \
        {{ if vmid != "" { "--vmid " + vmid } else { "" } }} \
        {{ if yes == "true" { "--yes" } else { "" } }}
