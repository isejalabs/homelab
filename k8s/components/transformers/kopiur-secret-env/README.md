## Purpose

Rewrites `kopiur-secret`'s `ExternalSecret` (`kopiur-repository`) to pull the correct per-environment 1Password section, e.g. `kopiur-backup#base` → `kopiur-backup#dev`. Every environment has its own bucket and credentials (matching `kopiur-repository`'s own per-env pattern), so this can't be hardcoded once in the shared `kopiur-secret` component.

## How it works

Same mechanism as `replace-path`/`prefix-domain`: a kustomize `replacements` entry sources `CLUSTER_ENVIRONMENT` from the `cluster-param` `ConfigMap` (populated per-env by `k8s/components/envs/<env>/cluster-param.yaml`) and replaces the last `#`-delimited segment of the target field:

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

`kopiur-backup#base` splits into `["kopiur-backup", "base"]` on `#`; `index: 1` replaces the second element (`"base"`) with the sourced environment name.

## Where it's included

Registered per-env (alongside `prefix-domain`) in every `k8s/components/envs/<env>/kustomization.yaml`, not in `envs/base/` — like `prefix-domain`, it needs `cluster-param`'s actual `CLUSTER_ENVIRONMENT` value, which only exists once a specific environment's component is included, not in the shared base.

## No-op safety

The `select` targets `kind: ExternalSecret, name: kopiur-repository` specifically. For any app that doesn't include the `kopiur-backup` component at all, nothing matches and the replacement silently no-ops — same behavior as `prefix-domain`'s `Ingress`/`HTTPRoute`/`TLSRoute` replacements for apps with none of those resources. No app-level wiring or opt-out is needed either way.

See [docs/kopiur-backup-restore.md](../../../../docs/kopiur-backup-restore.md) for the full backup/restore mechanism this supports.
