set default-list
set default-script
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[doc('List Longhorn volume snapshots (hourly/daily RecurringJob + manual), newest first, for one app or every app in scope (-n <ns>|-A required; app optional; -e/--environment optional, defaults to the current kubecontext). Hourly snapshots only go back ~24h.')]
[arg('environment', short='e', long='environment')]
[arg('namespace', short='n', long='namespace')]
[arg('all_namespaces', short='A', long='all-namespaces', value='true')]
list app="" environment="" namespace="" all_namespaces="false":
    "{{ justfile_directory() }}/scripts/longhorn-snapshot-list.sh" {{ app }} \
        {{ if environment != "" { "-e" } else { "" } }} {{ environment }} \
        {{ if namespace != "" { "-n" } else { "" } }} {{ namespace }} \
        {{ if all_namespaces == "true" { "-A" } else { "" } }}

[doc('Trigger a manual Longhorn snapshot: one named app (PVC), or every Longhorn volume in scope with --all (-n <ns>|-A required; -e/--environment optional, defaults to the current kubecontext). Manual snapshots are never pruned automatically.')]
[arg('environment', short='e', long='environment')]
[arg('namespace', short='n', long='namespace')]
[arg('all_namespaces', short='A', long='all-namespaces', value='true')]
[arg('all', long='all', value='true')]
create app="" environment="" namespace="" all_namespaces="false" all="false":
    "{{ justfile_directory() }}/scripts/longhorn-snapshot-create.sh" {{ app }} \
        {{ if environment != "" { "-e" } else { "" } }} {{ environment }} \
        {{ if namespace != "" { "-n" } else { "" } }} {{ namespace }} \
        {{ if all_namespaces == "true" { "-A" } else { "" } }} \
        {{ if all == "true" { "--all" } else { "" } }}

[doc('Roll an app back to a Longhorn snapshot (-e/--environment -n <ns> required; --snapshot <name> | --at <RFC3339 UTC ts>, default latest; Deployments only; scales the app down and pauses for a manual revert in the Longhorn UI; takes a pre-restore-* safety snapshot first)')]
restore app *flags:
    "{{ justfile_directory() }}/scripts/longhorn-snapshot-restore.sh" {{ app }} {{ flags }}
