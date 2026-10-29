set default-list
set default-script
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[doc('List the Keycloak database dumps in the environment bucket, key / last modified / size (-e/--environment required)')]
list *flags:
    "{{ justfile_directory() }}/scripts/keycloak-db-restore.sh" --list {{ flags }}

[doc('Restore the Keycloak database from a dump through a verified swap; the old database is kept (-e/--environment required; --dump <key>|latest, default latest; -y skips the confirmation)')]
restore *flags:
    "{{ justfile_directory() }}/scripts/keycloak-db-restore.sh" {{ flags }}
