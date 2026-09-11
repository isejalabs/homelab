## Purpose

Shared kustomize `Component` wiring credentials for [kopiur](https://github.com/home-operations/kopiur), the backup operator this cluster uses.

- **`secret/`** — a `kopiur-repository-secret` `ExternalSecret`, namespaced wherever it's included. The mover Job that talks to `fiona` needs these credentials in its *own* namespace (`envFrom` is namespace-local), so every consumer includes this component rather than referencing a single shared `Secret` — `kopiur-repository` itself (in `kopiur-system`) includes it the same way `apps/storage/pvc`/`pvc-no-backup` do.

Apps don't include `secret/` directly — it's pulled in automatically by [`apps/storage/pvc`](../storage/pvc) and [`apps/storage/pvc-no-backup`](../storage/pvc-no-backup), which is what an app actually wires into its own `base/kustomization.yaml`. See [apps/storage/README.md](../storage/README.md) for that side, and [docs/kopiur-backup-restore.md](../../../../docs/kopiur-backup-restore.md) for how the backup/restore mechanism itself works.
