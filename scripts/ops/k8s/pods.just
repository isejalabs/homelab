set default-list
set default-script
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

# Absorbs leftover arguments and lists the recipes instead, same as in `proxmox/vm.just`.
[private]
default *args:
    {{ just_executable() }} --justfile {{ source_file() }} --list

[arg('environment', long='environment', short='e')]
[arg('namespace', long='namespace', short='n')]
[doc('List pods that are not healthy (CrashLoopBackOff, Error, Pending, not ready, ...) without completed jobs (-e/--environment optional, defaults to the current kubecontext; -n/--namespace optional, defaults to all namespaces)')]
list-failed environment="" namespace="":
    "{{ justfile_directory() }}/scripts/ops/k8s/pods-list-failed.sh" \
        {{ if environment != "" { "-e" } else { "" } }} {{ environment }} \
        {{ if namespace != "" { "-n" } else { "" } }} {{ namespace }}
