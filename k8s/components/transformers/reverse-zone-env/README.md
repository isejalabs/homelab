## Purpose

Wires each environment's own PTR-zone name (e.g. `3.8.10.in-addr.arpa` for `dev`, matching its `10.8.3.0/24` LB-IP pool) into both PowerDNS's zone-bootstrap `initContainer` and external-dns's `domainFilters`/`--rfc2136-zone`, so external-dns's `--create-ptr` can write PTR records for that range. Unlike the forward `<env>.iseja.net` zone (see [`replace-domain`](../replace-domain)), this value isn't derivable from `DOMAIN_BASE`/`DOMAIN_TLD` — it's tied to each environment's own Cilium LB-IPAM pool (`k8s/infra/kube-system/cilium/envs/<env>/ip-pool-bgp.yaml`), a completely unrelated addressing scheme — so it comes from its own per-env `DNS_REVERSE_ZONE`/`DNS_ZONE` `cluster-param` fields instead of a `DOMAIN_BASE`/`DOMAIN_TLD` string-split. See [`k8s/apps/dns/powerdns/README.md`](../../../apps/dns/powerdns/README.md#per-environment-ptrreverse-zone-setup) for how a new environment sets these fields.

## How it works

Two files, both sourcing from `cluster-param` (populated per-env by `k8s/components/envs/<env>/cluster-param.yaml`):

`repl/helmrelease-powerdns-ptr.yaml` copies `DNS_REVERSE_ZONE` wholesale into PowerDNS's `REVERSE_ZONE` env var, in both the main container and the `bootstrap-zone` init container (two separate fields even though they're aliased in the base YAML — kustomize resolves the alias before patching, so both need their own target):

```yaml
- source:
    kind: ConfigMap
    name: cluster-param
    fieldPath: data.DNS_REVERSE_ZONE
  targets:
    - select:
        kind: HelmRelease
        name: powerdns
      fieldPaths:
        - spec.values.controllers.main.containers.main.env.REVERSE_ZONE
        - spec.values.controllers.main.initContainers.bootstrap-zone.env.REVERSE_ZONE
```

`repl/helmrelease-external-dns-ptr.yaml` does the equivalent for external-dns, but needs two different values: `DNS_ZONE` (the already-resolved *forward* zone value, kept as its own `cluster-param` literal rather than chained from `replace-domain`'s own output — see the file's own comment for why: it also runs, harmlessly via `targets.select`, against every other app's build in the same environment, where no `external-dns` `HelmRelease` exists at all, and *sourcing* from one there — unlike a `targets.select` with zero matches — is a hard build error, not a silent no-op) spliced into `extraArgs`' `--rfc2136-zone=<forward-zone>` entry, and `DNS_REVERSE_ZONE` spliced into both `domainFilters.1` and `extraArgs`' `--rfc2136-zone=<reverse-zone>` entry. Both extraArgs splices use `=` as the delimiter, never `.` — a real zone name always contains dots, and dot-splitting a combined `--flag=value` string risks corrupting the `--rfc2136-zone=` prefix itself (see [`docs/architecture/kustomize.md`](../../../../docs/architecture/kustomize.md) and the file's own comments for the full reasoning).

## Where it's included

Registered per-env (alongside `powerdns-tsig-env`) in every `k8s/components/envs/<env>/kustomization.yaml`, not in `envs/base/` — it needs `cluster-param`'s actual `DNS_REVERSE_ZONE`/`DNS_ZONE` values, which only exist once a specific environment's component is included, not in the shared base.

## No-op safety

Each `select` targets one `HelmRelease` by name specifically (`powerdns` or `external-dns`). For any app build that doesn't include either `HelmRelease` at all, the `targets.select` simply matches nothing and no-ops — same behavior as `powerdns-tsig-env`. The one exception, already covered above: a `source` (not a `targets.select`) referencing a `HelmRelease` that doesn't exist in the current build is a hard error, which is exactly why `helmrelease-external-dns-ptr.yaml` sources `DNS_ZONE` from `cluster-param` rather than chaining off `replace-domain`'s already-resolved output on the `external-dns` `HelmRelease` itself.
