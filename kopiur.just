set default-list
set default-script
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[doc('List kopiur snapshots for an app (-e <env> -n <ns> required)')]
snapshots app *flags:
    "{{ justfile_directory() }}/scripts/kopiur-snapshots.sh" {{ app }} {{ flags }}

[doc('Trigger a manual kopiur backup for an app (-e <env> -n <ns> required)')]
backup app *flags:
    "{{ justfile_directory() }}/scripts/kopiur-backup.sh" {{ app }} {{ flags }}

[doc('Trigger a manual kopiur backup for every app (-e <env> required, plus -n <ns> or -A)')]
backup-all *flags:
    "{{ justfile_directory() }}/scripts/kopiur-backup-all.sh" {{ flags }}

[doc('Restore an app from its latest kopiur snapshot (-e <env> -n <ns> required; deletes and repopulates its PVC)')]
restore app *flags:
    "{{ justfile_directory() }}/scripts/kopiur-restore.sh" {{ app }} {{ flags }}
