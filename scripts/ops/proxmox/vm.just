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

[arg('environment', long='environment', short='e')]
[doc('List the Proxmox VMs of an environment via the Proxmox API (-e/--environment required)')]
list environment:
    "{{ justfile_directory() }}/scripts/ops/proxmox/vm-list.sh" -e {{ environment }}

[arg('environment', long='environment', short='e')]
[arg('vmid', long='vmid')]
[doc('Start every VM in an environment, or just one with --vmid, via the Proxmox API (-e/--environment required; safe, never prompts)')]
start environment vmid="":
    "{{ justfile_directory() }}/scripts/ops/proxmox/vm-power.sh" --action start -e {{ environment }} \
        {{ if vmid != "" { "--vmid " + vmid } else { "" } }}

[arg('environment', long='environment', short='e')]
[arg('vmid', long='vmid')]
[arg('yes', long='yes', short='y', value='true')]
[doc('Gracefully shut down every VM in an environment, or just one with --vmid, via the Proxmox API (-e/--environment required; destructive -- prompts for confirmation unless --yes or --vmid is given)')]
shutdown environment vmid="" yes="false":
    "{{ justfile_directory() }}/scripts/ops/proxmox/vm-power.sh" --action shutdown -e {{ environment }} \
        {{ if vmid != "" { "--vmid " + vmid } else { "" } }} \
        {{ if yes == "true" { "--yes" } else { "" } }}

[arg('environment', long='environment', short='e')]
[arg('vmid', long='vmid')]
[arg('yes', long='yes', short='y', value='true')]
[doc('Hard-stop every VM in an environment, or just one with --vmid, via the Proxmox API (-e/--environment required; destructive -- prompts for confirmation unless --yes or --vmid is given)')]
stop environment vmid="" yes="false":
    "{{ justfile_directory() }}/scripts/ops/proxmox/vm-power.sh" --action stop -e {{ environment }} \
        {{ if vmid != "" { "--vmid " + vmid } else { "" } }} \
        {{ if yes == "true" { "--yes" } else { "" } }}

[arg('environment', long='environment', short='e')]
[arg('vmid', long='vmid')]
[arg('yes', long='yes', short='y', value='true')]
[doc('Hard-reset every VM in an environment, or just one with --vmid, via the Proxmox API (-e/--environment required; destructive -- prompts for confirmation unless --yes or --vmid is given)')]
reset environment vmid="" yes="false":
    "{{ justfile_directory() }}/scripts/ops/proxmox/vm-power.sh" --action reset -e {{ environment }} \
        {{ if vmid != "" { "--vmid " + vmid } else { "" } }} \
        {{ if yes == "true" { "--yes" } else { "" } }}
