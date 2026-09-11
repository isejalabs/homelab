## Purpose

Rewrites `kopiur-repository`'s per-environment values so `base/` only needs to state them once as
`base-kopiur-backup`/`kopiur-backup#base`:

- the `ExternalSecret`'s 1Password section, e.g. `kopiur-backup#base` → `kopiur-backup#dev`
- the `ClusterRepository`'s S3 bucket name, e.g. `base-kopiur-backup` → `dev-kopiur-backup`

Every environment has its own bucket and credentials (matching `kopiur-repository`'s own per-env
pattern), so neither of these can be hardcoded once in the shared `base/`.

## How it works

Same mechanism as `replace-path`/`prefix-domain`: two kustomize `replacements` entries, both sourcing
`CLUSTER_ENVIRONMENT` from the `cluster-param` `ConfigMap` (populated per-env by
`k8s/components/envs/<env>/cluster-param.yaml`).

`repl/externalsecret-kopiur-key.yaml` replaces the last `#`-delimited segment of the `ExternalSecret` key:

```yaml
- source:
    kind: ConfigMap
    name: cluster-param
    fieldPath: data.CLUSTER_ENVIRONMENT
  targets:
    - select:
        kind: ExternalSecret
        name: kopiur-repository
      fieldPaths:
        - spec.dataFrom.0.extract.key
      options:
        delimiter: "#"
        index: 1
```

`kopiur-backup#base` splits into `["kopiur-backup", "base"]` on `#`; `index: 1` replaces the second
element (`"base"`) with the sourced environment name.

`repl/clusterrepository-bucket.yaml` replaces the first `-`-delimited segment of the `ClusterRepository`'s
bucket name:

```yaml
- source:
    kind: ConfigMap
    name: cluster-param
    fieldPath: data.CLUSTER_ENVIRONMENT
  targets:
    - select:
        kind: ClusterRepository
        name: fiona
      fieldPaths:
        - spec.backend.s3.bucket
      options:
        delimiter: "-"
        index: 0
```

`base-kopiur-backup` splits into `["base", "kopiur", "backup"]` on `-`; `index: 0` replaces only the
first element (`"base"`) with the sourced environment name — the extra hyphen inside `kopiur-backup`
itself doesn't matter, since only the first segment is targeted.

## Where it's included

Registered per-env (alongside `prefix-domain`) in every `k8s/components/envs/<env>/kustomization.yaml`,
not in `envs/base/` — like `prefix-domain`, it needs `cluster-param`'s actual `CLUSTER_ENVIRONMENT`
value, which only exists once a specific environment's component is included, not in the shared base.

## No-op safety

Each `select` targets a specific `kind`+`name` (`ExternalSecret`/`kopiur-repository`,
`ClusterRepository`/`fiona`). For any app that doesn't include the `kopiur-backup` component at all,
neither matches and the replacement silently no-ops — same behavior as `prefix-domain`'s
`Ingress`/`HTTPRoute`/`TLSRoute` replacements for apps with none of those resources. No app-level wiring
or opt-out is needed either way.

See [docs/kopiur-backup-restore.md](../../../../docs/kopiur-backup-restore.md) for the full backup/restore mechanism this supports.
