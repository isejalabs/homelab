set default-list
set default-script
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[doc('List kopiur snapshots for an app')]
snapshots app ns="":
    ns="{{ ns }}"; ns="${ns:-$(kubectl config view --minify -o jsonpath='{..namespace}')}"
    kubectl get snapshot -n "${ns}" -l kopiur.home-operations.com/config={{ app }} \
        -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,ORIGIN:.status.origin,KOPIA_ID:.status.snapshot.kopiaSnapshotID,SIZE:.status.stats.sizeBytes,CREATED:.metadata.creationTimestamp

[doc('Trigger a manual kopiur backup for an app')]
backup app ns="":
    bash "{{ justfile_directory() }}/scripts/kopiur-backup.sh" {{ app }} {{ ns }}

[doc('Trigger a manual kopiur backup for every app')]
backup-all ns="":
    bash "{{ justfile_directory() }}/scripts/kopiur-backup-all.sh" {{ ns }}

[doc('Restore an app from its latest kopiur snapshot (deletes and repopulates its PVC)')]
restore app ns="" deploy="":
    bash "{{ justfile_directory() }}/scripts/kopiur-restore.sh" {{ app }} {{ ns }} {{ deploy }}
