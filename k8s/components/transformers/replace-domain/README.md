## Purpose

Swaps the placeholder domain `example.com`, which `base/` uses everywhere (never a real domain), for the environment's own domain: `DOMAIN_BASE` and `DOMAIN_TLD` from the `cluster-param` ConfigMap of [`components/envs/<env>`](../../envs). `adguard.example.com` becomes `adguard.dev.iseja.net` in `dev` and `adguard.prod.iseja.net` in `prod`. The `<env>-` prefix that every other environment puts in front of the hostname is a separate step, see [`prefix-domain`](../prefix-domain/README.md).

## How it works

A hostname such as `adguard.example.com` is split on `.` and two segments are replaced, each by its own `replacements` entry: segment 2 (`com`) by `DOMAIN_TLD` (`net`), segment 1 (`example`) by `DOMAIN_BASE` (`dev.iseja`):

```yaml
- source:
    kind: ConfigMap
    name: cluster-param
    fieldPath: data.DOMAIN_TLD
  targets:
    - select:
        kind: HTTPRoute
      reject:
        - name: http-redirect-to-https
      fieldPaths:
        - spec.hostnames.*
      options:
        delimiter: "."
        index: 2
```

The TLD entry comes first in every file, and that order matters: `DOMAIN_BASE` itself contains a dot (`dev.iseja`), so replacing it first would add a segment and the TLD replacement would hit the wrong one. A value without a label segment (PowerDNS's `ZONE` is `example.com` itself) is one segment shorter, so it uses indexes 1 and 0 instead of 2 and 1.

What it rewrites, one file per kind in [`repl/`](repl):

| Kind | Field | File |
| --- | --- | --- |
| `HTTPRoute` | `spec.hostnames.*` | [`httproute-replace-domain.yaml`](repl/httproute-replace-domain.yaml) |
| `TLSRoute` | `spec.hostnames.*` | [`tlsroute-replace-domain.yaml`](repl/tlsroute-replace-domain.yaml) |
| `Gateway` | `spec.listeners.*.hostname` | [`gateway-replace-hostname.yaml`](repl/gateway-replace-hostname.yaml) |
| `Gateway` | the `external-dns.kubernetes.io/target` and `.../hostname` annotations | [`gateway-external-dns-hostname.yaml`](repl/gateway-external-dns-hostname.yaml) |
| `Certificate` | `spec.dnsNames.*` | [`cert-replace-hostname.yaml`](repl/cert-replace-hostname.yaml) |
| `Keycloak` | `spec.hostname.hostname` | [`keycloak-replace-domain.yaml`](repl/keycloak-replace-domain.yaml) |
| `Service` `unbound`, `adguard`, `unifi-controller`, `whoami` | the `external-dns.kubernetes.io/hostname` annotation | [`service-replace-domain.yaml`](repl/service-replace-domain.yaml) |
| `HelmRelease` `powerdns` | the `ZONE` env var (main and `bootstrap-zone` container) and the Service's hostname annotation | [`helmrelease-powerdns-zone.yaml`](repl/helmrelease-powerdns-zone.yaml) |
| `HelmRelease` `external-dns` | `domainFilters.0` | [`helmrelease-external-dns-zone.yaml`](repl/helmrelease-external-dns-zone.yaml) |
| `Ingress` | `spec.rules.0.host` | [`ingress-replace-domain.yaml`](repl/ingress-replace-domain.yaml) |

Two details worth knowing before adding an entry:

- `http-redirect-to-https` (`HTTPRoute`) and `internal-http` (`Gateway`) are rejected on purpose: they have no hostname by design, and a wildcard `fieldPaths` entry that matches nothing is a hard kustomize error, not a no-op.
- `external-dns` `domainFilters.0` is index 0 specifically, not `domainFilters.*`: index 1 is the PTR zone, an `in-addr.arpa.` name that must not go through this split, see [`reverse-zone-env`](../reverse-zone-env/README.md).

No `Ingress` exists in the repo today (apps use the Gateway API), so that entry has nothing to match; it is kept for completeness. The `Keycloak` hostname goes through the same pair as the `HTTPRoute`, so the two cannot drift; the one hand-typed copy is the `keycloak_url` of each `keycloak-realm` Terragrunt unit, which `scripts/kustomize-build-all.sh` checks against both.

## Where it's included

Through [`components/envs/base`](../../envs/base/kustomization.yaml), so all 8 environments get it, `prod` included. Each `select` targets a kind (or a named object), so a unit that has none of them is unchanged.

[`docs/architecture/kustomize.md`](../../../../docs/architecture/kustomize.md#transformers-and-replacements) walks through how the pieces fit together, and [`docs/architecture/network.md`](../../../../docs/architecture/network.md) explains why the Gateway and Service annotations exist.
