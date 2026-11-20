set default-list
set default-script
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[arg('all_namespaces', long='all-namespaces', short='A', value='true')]
[arg('environment', long='environment', short='e')]
[arg('namespace', long='namespace', short='n')]
[doc('List kopiur snapshots, for one app or every app in scope (-n <ns>|-A required; app optional; -e/--environment optional, defaults to the current kubecontext)')]
list app="" environment="" namespace="" all_namespaces="false":
    "{{ justfile_directory() }}/scripts/ops/kopiur/list.sh" {{ app }} \
        {{ if environment != "" { "-e" } else { "" } }} {{ environment }} \
        {{ if namespace != "" { "-n" } else { "" } }} {{ namespace }} \
        {{ if all_namespaces == "true" { "-A" } else { "" } }}

[arg('all', long='all', value='true')]
[arg('all_namespaces', long='all-namespaces', short='A', value='true')]
[arg('environment', long='environment', short='e')]
[arg('namespace', long='namespace', short='n')]
[doc('Trigger a manual kopiur backup: one named app, or every app in scope with --all (-n <ns>|-A required; -e/--environment optional, defaults to the current kubecontext)')]
create app="" environment="" namespace="" all_namespaces="false" all="false":
    "{{ justfile_directory() }}/scripts/ops/kopiur/create.sh" {{ app }} \
        {{ if environment != "" { "-e" } else { "" } }} {{ environment }} \
        {{ if namespace != "" { "-n" } else { "" } }} {{ namespace }} \
        {{ if all_namespaces == "true" { "-A" } else { "" } }} \
        {{ if all == "true" { "--all" } else { "" } }}

[doc('Restore an app from its latest kopiur snapshot (-e/--environment -n <ns> required; deletes and repopulates its PVC)')]
restore app *flags:
    "{{ justfile_directory() }}/scripts/ops/kopiur/restore.sh" {{ app }} {{ flags }}

[doc('Give an app a blank PVC, bypassing (not deleting) its existing kopiur backups, for importing data by other means (e.g. from another environment) -- interactive: waits for confirmation before restoring normal restore-on-loss wiring (-e/--environment -n <ns> required)')]
bypass-restore app *flags:
    "{{ justfile_directory() }}/scripts/ops/kopiur/bypass-restore.sh" {{ app }} {{ flags }}

[doc('Migrate an app from an old (e.g. proxmox-csi) PVC onto its new kopiur-managed PVC (-e/--environment -n <ns> --old-pvc required)')]
migrate new_pvc *flags:
    "{{ justfile_directory() }}/scripts/ops/kopiur/migrate-pvc.sh" {{ new_pvc }} {{ flags }}

[doc('Convert an existing kopiur-managed PVC onto a different StorageClass in place, e.g. ext4 -> xfs (-e/--environment -n <ns> --storage-class required)')]
convert-storage-class pvc *flags:
    "{{ justfile_directory() }}/scripts/ops/kopiur/convert-storageclass.sh" {{ pvc }} {{ flags }}
