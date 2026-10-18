---
status: current
---

# Longhorn Volume Snapshots

## Overview

[#1746](https://github.com/isejalabs/homelab/issues/1746): a `just backup::longhorn-snapshot::*` recipe set (`list`/`create`/`restore`, in `scripts/longhorn-snapshot.just`) for Longhorn's own local volume snapshots -- the ones the `hourly-snapshot` and `daily-backup` `RecurringJob`s create for every volume (`k8s/infra/longhorn-system/longhorn/base/job-*.yaml`), plus manual ones. This is the only protection in environments without a kopiur backup schedule (e.g. `dev` for apps not on `apps/storage/pvc`); for kopiur-backed apps see [`kopiur-backup-restore.md`](kopiur-backup-restore.md). Snapshots live on the same Longhorn volume as the data, so they protect against bad writes and mistakes, not against losing the volume or the cluster.

**Retention matters for choosing a snapshot**: `hourly-snapshot` keeps 24 snapshots, i.e. about the last 24 hours at hourly granularity (plus the `daily-backup` one). Unlike kopiur backups there is no day-based history, so snapshots are picked by exact timestamp, not by day.

`<app>` is the PVC name, as for the kopiur recipes. `-e/--environment` is optional for `list`/`create` (defaults to the current kubecontext) and required for `restore`.

## Daily tasks

```sh
just backup::longhorn-snapshot::list <app> -n <namespace>          # drop <app> to list every app; -A for all namespaces
just backup::longhorn-snapshot::create <app> -n <namespace>        # or --all (-n <ns> | -A) for every Longhorn volume in scope
```

A manual snapshot has no `RecurringJob` label, so no retain count ever prunes it. Delete it with `kubectl -n longhorn-system delete snapshots.longhorn.io <name>`.

## Restore an app to a snapshot

```sh
just backup::longhorn-snapshot::restore <app> -e <env> -n <namespace>                         # newest snapshot
just backup::longhorn-snapshot::restore <app> -e <env> -n <namespace> --snapshot <name>       # an exact snapshot
just backup::longhorn-snapshot::restore <app> -e <env> -n <namespace> --at 2026-10-17T14:00:00Z   # newest at or before a UTC time
```

Deployments only (`--deploy <name>` if the Deployment is named differently from the PVC). The recipe:

1. selects the snapshot and asks for confirmation (the revert discards everything written afterwards);
2. takes a `pre-restore-*` safety snapshot of the current data -- if the restore was a mistake, rerun with `--snapshot <that name>`;
3. suspends the owning Flux object, scales the Deployment to 0 and waits for the volume to detach;
4. **pauses for you to do the revert in the Longhorn UI**: attach the volume with "Maintenance mode" ticked, open the snapshot, Revert, then detach again;
5. after you confirm (and it verified the volume is detached), resumes Flux and scales back up.

The revert is manual on purpose: Longhorn exposes it only through the longhorn-manager API (no CRD), which the planned authentication in [#1725](https://github.com/isejalabs/homelab/issues/1725) will lock down. The PV and PVC are never touched, so kopiur's restore-on-create wiring is undisturbed. StatefulSet support is a possible later stage (for this module and kopiur alike).
