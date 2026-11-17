# Immich database restore

Wrapped by `just backup::immich::<list|restore>` (see [`mod.just`](mod.just); the recipes pass their flags straight to the script, which can also be run directly) and always against one environment — see [`docs/backup/immich-database.md`](../../../docs/backup/immich-database.md#restore) for the procedure, the safety reasoning and the drill record. The script documents its purpose and usage in a header comment; this README is an index, not a duplicate of that.

| Script | Purpose |
| --- | --- |
| [`mod.just`](mod.just) | the `just` recipes `list` and `restore` |
| [`db-restore.sh`](db-restore.sh) | restores the Immich database from a `pg_dump` in the `<env>-immich-db` bucket, into a live or a fresh, empty cluster: verifies the dump in a scratch database first, then stops Flux/the Immich workloads/the dump CronJob, swaps the databases by renaming (the old one is kept) and starts the workloads again; `--list` shows the available dumps; `--identity <file>` is the age private key for an encrypted `*.dump.age` dump |

Sources [`lib/common.sh`](../../lib/common.sh) for logging, environment validation and kubecontext construction. Needs `kubectl`, `flux`, `gum` and `jq`. Adapted from [`../keycloak/db-restore.sh`](../keycloak/db-restore.sh).
