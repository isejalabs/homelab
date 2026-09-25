## Purpose

Rewrites each of powerdns's `ExternalSecret`s' per-environment 1Password key so `base/` only needs to state
it once as `<name>#base` — same mechanism as [`kopiur-secret-env`](../kopiur-secret-env/README.md), applied
to a different resource kind. Each environment's PowerDNS uses its own TSIG keys so a compromised key in one
environment (e.g. `dbg`) can't be used to forge updates/transfers in another (e.g. `prod`).

Two entries today: `powerdns-tsig-dynupdate` (RFC2136 dynamic updates from external-dns) and
`powerdns-tsig-axfr-out` (AXFR to `10.7.2.12`, the LXC secondary) — deliberately separate keys, never reused
between each other, since each authorizes a different trust relationship. Naming each by its role means a
future `powerdns-tsig-axfr-in` (UCS → PowerDNS, prod-only, root-zone cutover phase) can be added later
without renaming anything that already exists.

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
    - select:
        kind: ExternalSecret
        name: powerdns-tsig-axfr-out
      fieldPaths:
        - spec.dataFrom.0.extract.key
      options:
        delimiter: "#"
        index: 1
```

`powerdns-tsig-dynupdate#base` splits into `["powerdns-tsig-dynupdate", "base"]` on `#`; `index: 1` replaces
the second element (`"base"`) with the sourced environment name — same for `powerdns-tsig-axfr-out#base`.

A future `powerdns-tsig-axfr-in` `ExternalSecret` (prod-only, root-zone cutover phase) gets its own `targets`
entry appended to this same file rather than a sibling transformer component — same shape, same mechanism,
just one more entry in the list, the same way `kopiur-secret-env` itself bundles two unrelated-resource-kind
replacements (`ExternalSecret` and `ClusterRepository`) under one purpose-named component.

## Where it's included

Registered per-env (alongside `kopiur-secret-env`) in every `k8s/components/envs/<env>/kustomization.yaml`,
not in `envs/base/` — it needs `cluster-param`'s actual `CLUSTER_ENVIRONMENT` value, which only exists once a
specific environment's component is included, not in the shared base.

## No-op safety

Each `select` targets one `ExternalSecret` by name specifically. For any app that doesn't include that
particular `ExternalSecret` at all, it simply matches nothing and no-ops — same behavior as
`kopiur-secret-env`.

## 1Password items

One item per environment per key — `powerdns-tsig-dynupdate#<env>` and `powerdns-tsig-axfr-out#<env>` (e.g.
`powerdns-tsig-dynupdate#dev`) — in the shared `K8S` vault. See
[`k8s/apps/dns/powerdns/README.md`](../../../apps/dns/powerdns/README.md) for the exact key-generation
commands, field names, and setup steps.
