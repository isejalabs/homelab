## Purpose

Puts the environment name in front of the hostname in every non-prod environment: `adguard.dev.iseja.net` (the result of [`replace-domain`](../replace-domain/README.md)) becomes `dev-adguard.dev.iseja.net`.

`prod` is the one environment that does not include it, so its hostnames stay `adguard.prod.iseja.net`. See [`reference/environments.md`](../../../../docs/reference/environments.md#domain-and-naming) for the naming scheme.

## How it works

Each `replacements` entry takes `CLUSTER_ENVIRONMENT` from the `cluster-param` ConfigMap and applies it to a hostname field with `delimiter: "-"` and `index: -1`, which prepends the value joined by that delimiter:

```yaml
- source:
    kind: ConfigMap
    name: cluster-param
    fieldPath: data.CLUSTER_ENVIRONMENT
  targets:
    - select:
        kind: HTTPRoute
      reject:
        - name: http-redirect-to-https
      fieldPaths:
        - spec.hostnames.*
      options:
        delimiter: "-"
        index: -1
```

What it rewrites, one file per kind in [`repl/`](repl). The targets are the same as in `replace-domain`, minus the ones that must keep the bare domain:

| Kind | Field | File |
| --- | --- | --- |
| `HTTPRoute` | `spec.hostnames.*` | [`httproute-prefix-domain.yaml`](repl/httproute-prefix-domain.yaml) |
| `TLSRoute` | `spec.hostnames.*` | [`tlsroute-prefix-domain.yaml`](repl/tlsroute-prefix-domain.yaml) |
| `Gateway` | the `external-dns.kubernetes.io/target` annotation and the `external-dns.kubernetes.io/hostname` annotation under `spec.infrastructure.annotations` | [`gateway-external-dns-hostname.yaml`](repl/gateway-external-dns-hostname.yaml) |
| `Keycloak` | `spec.hostname.hostname` | [`keycloak-prefix-domain.yaml`](repl/keycloak-prefix-domain.yaml) |
| `Service` `unbound`, `adguard`, `unifi-controller`, `whoami` | the `external-dns.kubernetes.io/hostname` annotation | [`service-prefix-domain.yaml`](repl/service-prefix-domain.yaml) |
| `Ingress` | `spec.rules.*.host` | [`ingress-prefix-domain.yaml`](repl/ingress-prefix-domain.yaml) |

Deliberately **not** prefixed:

- `Gateway` listener hostnames and `Certificate` `dnsNames`: they are wildcards below the environment's domain, which already cover the prefixed hostnames.
- The PowerDNS and external-dns zone settings: they name a zone, not a host.

The Service targets are listed by name because only those Services carry the annotation; for `HTTPRoute` every instance of the kind does, so it is selected by kind (rejecting `http-redirect-to-https`, which has no hostname).

## Where it's included

Per environment, not through `envs/base`: [`components/envs/<env>/kustomization.yaml`](../../envs) includes it in `dbg`, `dev`, `head`, `poc`, `qa`, `rebuild` and `src`. In [`prod`](../../envs/prod/kustomization.yaml) the line is commented out, which is the whole mechanism for keeping prod's hostnames unprefixed.

See [`docs/architecture/kustomize.md`](../../../../docs/architecture/kustomize.md#transformers-and-replacements) for how the transformers fit together.
