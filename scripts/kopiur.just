set default-list
set default-script
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[doc('List kopiur snapshots for an app (-n <ns> required; -e/--environment optional, defaults to the current kubecontext)')]
list app *flags:
    "{{ justfile_directory() }}/scripts/kopiur-list.sh" {{ app }} {{ flags }}

[doc('Trigger a manual kopiur backup: one named app, or every app in scope with --all (-n <ns>|-A required; -e/--environment optional, defaults to the current kubecontext)')]
[arg('environment', short='e', long='environment')]
[arg('namespace', short='n', long='namespace')]
[arg('all_namespaces', short='A', long='all-namespaces', value='true')]
[arg('all', long='all', value='true')]
create app="" environment="" namespace="" all_namespaces="false" all="false":
    "{{ justfile_directory() }}/scripts/kopiur-create.sh" {{ app }} \
        {{ if environment != "" { "-e" } else { "" } }} {{ environment }} \
        {{ if namespace != "" { "-n" } else { "" } }} {{ namespace }} \
        {{ if all_namespaces == "true" { "-A" } else { "" } }} \
        {{ if all == "true" { "--all" } else { "" } }}

[doc('Restore an app from its latest kopiur snapshot (-e/--environment -n <ns> required; deletes and repopulates its PVC)')]
restore app *flags:
    "{{ justfile_directory() }}/scripts/kopiur-restore.sh" {{ app }} {{ flags }}
