## Purpose

Forces every `SnapshotSchedule` object to `spec.schedule.suspend: true`, regardless of which storage
component (`apps/storage/pvc` or `pvc-no-backup`) an app picked, or what value it set. Used as a guardrail
in environments that shouldn't run active backup schedules at all (`dbg`/`head`/`poc`/`src` as of this
writing) — an app there would have to deliberately choose `pvc/` over `pvc-no-backup/` for this to matter,
but the env-level override wins either way.

## How it works

A JSON6902 patch, applied broadly by `kind` with no `name` filter — so it matches every `SnapshotSchedule`
regardless of its per-app `${APP}`-templated name:

```yaml
- op: replace
  path: /spec/schedule/suspend
  value: true
```

For any app that doesn't include `apps/storage/pvc` at all (e.g. one using `pvc-no-backup`), there's no
`SnapshotSchedule` object to match, so this silently no-ops — same safety property as
`kopiur-secret-env`/`prefix-domain`'s broad selectors elsewhere in this repo.

## Where it's included

Registered per-env, only in `k8s/components/envs/{dbg,head,poc,src}/kustomization.yaml` — the environments
that get a real RustFS bucket (so `kopiur-repository`'s `ClusterRepository` has something to connect to)
but no active schedule. Not registered in `dev`/`qa`/`rebuild`/`prod`.
