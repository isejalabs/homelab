## Purpose

Rewrites `powerdns-tsig-dynupdate`'s per-environment 1Password key so `base/` only needs to state it once as
`powerdns-tsig-dynupdate#base` — same mechanism as [`kopiur-secret-env`](../kopiur-secret-env/README.md),
applied to a different `ExternalSecret`. Each environment's PowerDNS uses its own TSIG key so a compromised
key in one environment (e.g. `dbg`) can't be used to forge dynamic updates in another (e.g. `prod`).

Named `powerdns-tsig-dynupdate`, not just `powerdns-tsig`: this key authorizes one specific thing (RFC2136
dynamic updates from external-dns). Prod will later need its own separate `powerdns-tsig-axfr-out` (PowerDNS
→ the surviving LXC) and `powerdns-tsig-axfr-in` (UCS → PowerDNS) keys for the root-zone cutover phase —
different trust relationships, never reused from this one. Naming this one by its role up front means those
can be added later without renaming anything that already exists.

## How it works

Same mechanism as `kopiur-secret-env`: one kustomize `replacements` entry, sourcing `CLUSTER_ENVIRONMENT`
from the `cluster-param` `ConfigMap` (populated per-env by `k8s/components/envs/<env>/cluster-param.yaml`),
replacing the last `#`-delimited segment of the `ExternalSecret`'s key:

```yaml
- source:
    kind: ConfigMap
    name: cluster-param
    fieldPath: data.CLUSTER_ENVIRONMENT
  targets:
    - select:
        kind: ExternalSecret
        name: powerdns-tsig-dynupdate
      fieldPaths:
        - spec.dataFrom.0.extract.key
      options:
        delimiter: "#"
        index: 1
```

`powerdns-tsig-dynupdate#base` splits into `["powerdns-tsig-dynupdate", "base"]` on `#`; `index: 1` replaces
the second element (`"base"`) with the sourced environment name.

A future `powerdns-tsig-axfr-out`/`-in` `ExternalSecret` (prod-only) gets its own `targets` entry appended
to this same file rather than a sibling transformer component — same shape, same mechanism, just one more
entry in the list, the same way `kopiur-secret-env` itself bundles two unrelated-resource-kind replacements
(`ExternalSecret` and `ClusterRepository`) under one purpose-named component.

## Where it's included

Registered per-env (alongside `kopiur-secret-env`) in every `k8s/components/envs/<env>/kustomization.yaml`,
not in `envs/base/` — it needs `cluster-param`'s actual `CLUSTER_ENVIRONMENT` value, which only exists once a
specific environment's component is included, not in the shared base.

## No-op safety

`select` targets `ExternalSecret`/`powerdns-tsig-dynupdate` specifically. For any app that doesn't include
PowerDNS's `ExternalSecret` at all, it simply matches nothing and no-ops — same behavior as
`kopiur-secret-env`.

## 1Password item

One item per environment, named `powerdns-tsig-dynupdate#<env>` (e.g. `powerdns-tsig-dynupdate#dev`) in the
shared `K8S` vault, with a single field `TSIG_DYNUPDATE_SECRET` holding a base64 HMAC-SHA256 key (e.g.
`tsig-keygen -a hmac-sha256 dynupdate` or `openssl rand -base64 32`).
