## Purpose

Rewrites `powerdns-tsig`'s per-environment 1Password key so `base/` only needs to state it once as
`powerdns-tsig#base` — same mechanism as [`kopiur-secret-env`](../kopiur-secret-env/README.md), applied to a
different `ExternalSecret`. Each environment's PowerDNS uses its own TSIG key so a compromised key in one
environment (e.g. `dbg`) can't be used to forge dynamic updates in another (e.g. `prod`).

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
        name: powerdns-tsig
      fieldPaths:
        - spec.dataFrom.0.extract.key
      options:
        delimiter: "#"
        index: 1
```

`powerdns-tsig#base` splits into `["powerdns-tsig", "base"]` on `#`; `index: 1` replaces the second element
(`"base"`) with the sourced environment name.

## Where it's included

Registered per-env (alongside `kopiur-secret-env`) in every `k8s/components/envs/<env>/kustomization.yaml`,
not in `envs/base/` — it needs `cluster-param`'s actual `CLUSTER_ENVIRONMENT` value, which only exists once a
specific environment's component is included, not in the shared base.

## No-op safety

`select` targets `ExternalSecret`/`powerdns-tsig` specifically. For any app that doesn't include PowerDNS's
`ExternalSecret` at all, it simply matches nothing and no-ops — same behavior as `kopiur-secret-env`.

## 1Password item

One item per environment, named `powerdns-tsig#<env>` (e.g. `powerdns-tsig#dev`) in the shared `K8S` vault,
with a single field `TSIG_SECRET` holding a base64 HMAC-SHA256 key (e.g. `tsig-keygen -a hmac-sha256
external-dns` or `openssl rand -base64 32`). Only one field today because this key authorizes exactly one
thing — external-dns's dynamic updates into that environment's own `<env>.iseja.net` zone. The prod-only
cutover work (AXFR to the surviving LXC, AXFR from UCS) will need its own, separate TSIG keys/items later —
different trust relationships, not reused from this one.
