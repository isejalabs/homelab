# Gateway

The shared Gateway API entry points of each environment: the `Gateway` objects (`internal`, `internal-http`, `external`), the wildcard `Certificate` they serve, and the HTTP-to-HTTPS redirect. Every app's `HTTPRoute` attaches to one of them.

## At a glance

| | |
| --- | --- |
| Namespace | `gateway-api` |
| Runs in | all 8 environments (Flux set `minimal`); `poc` also has a `tls-passthrough` Gateway |
| Installed via | Raw Gateway API resources (`Gateway`, `HTTPRoute`, cert-manager `Certificate`); the implementation is [Cilium](../../kube-system/cilium/README.md) |
| Flux Kustomization | `gateway-api` (the unit is `gateway`), depends on `gateway-api-crds`, `infra-ns` |

## Purpose

One place that terminates TLS and routes by hostname, so apps only declare an `HTTPRoute`. The big picture, including DNS and the physical network: [`network.md`](../../../../docs/architecture/network.md#gateway-api-cilium-as-the-implementation).

## Where it is used

- **Used by**: every app that has a web UI (`HTTPRoute` with `parentRefs` to `internal` in `gateway-api`), see [`workloads.md`](../../../../docs/architecture/workloads.md). external-dns publishes each route as a CNAME to the Gateway's own name (below).
- **Depends on**: [`gateway-api-crds`](../gateway-api-crds/) for the CRDs, Cilium for the implementation and the address, cert-manager and the ClusterIssuer `cloudflare-cluster-issuer` (DNS-01) for the wildcard certificate, external-dns for the names.

## Access

| Gateway | Listener | Address | Use |
| --- | --- | --- | --- |
| `internal` | HTTPS 443, `*.<env>.iseja.net` | `10.8.<env-id>.80` | every app's `HTTPRoute` |
| `internal-http` | HTTP 80 | `10.8.<env-id>.80` (same address) | redirect to HTTPS only |
| `external` | HTTPS 443 | `10.8.<env-id>.83` | reserved for public routes; no route uses it |

The names are `gw-internal.<env>.iseja.net` and `gw-external.<env>.iseja.net` (with the prefix, `dev-gw-internal.dev.iseja.net`). `<env-id>` is the environment ID in [`reference/environments.md`](../../../../docs/reference/environments.md#environment-id), e.g. `10.8.3.80` for `dev`.

The certificate is a Let's Encrypt **production** one in `dev`, `prod`, `qa` and `rebuild`; `dbg`, `head`, `poc` and `src` use the **staging** CA, which browsers do not trust ([`network.md`](../../../../docs/architecture/network.md#gateway-api-cilium-as-the-implementation)). In `poc` the extra Gateway `tls-passthrough` (`10.8.6.82`) passes the TLS of `poc-unifi.poc.iseja.net` through to the backend.

## Updates

No version of its own: the resources follow the Gateway API CRDs ([`gateway-api-crds`](../gateway-api-crds/), capped for Cilium compatibility) and the Cilium release. A Cilium bump can change how Gateways are translated, so test it in a non-prod environment first.

## Operations

| Task | Doc |
| --- | --- |
| A name does not resolve or points to the wrong target | [`troubleshooting-dns.md`](../../../../docs/troubleshooting/troubleshooting-dns.md) |
| Let's Encrypt limits when `rebuild` is rebuilt repeatedly | [`network.md`](../../../../docs/architecture/network.md#lets-encrypt-production-limits-and-rebuild) |

## Cheat sheet

```sh
flux get ks gateway-api --context admin@<env>-homelab
kubectl get gateway,httproute -A --context admin@<env>-homelab
kubectl get certificate,secret -n gateway-api --context admin@<env>-homelab

# which routes attach to the internal Gateway, and is the certificate ready?
kubectl describe gateway internal -n gateway-api --context admin@<env>-homelab
kubectl get certificate cert -n gateway-api -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' --context admin@<env>-homelab
```

## Upstream

- Gateway API: <https://gateway-api.sigs.k8s.io/>
- Cilium's implementation: <https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/>

## Design notes

`http-route-redirect.yaml`'s `http-redirect-to-https` `HTTPRoute` has no `hostname` specification (it matches all hosts), so the domain-replacement/prefix components reject it by name to avoid a zero-match hard error - see `components/transformers/replace-domain/repl/httproute-replace-domain.yaml` and `components/transformers/prefix-domain/repl/httproute-prefix-domain.yaml`.

The route attaches to the `internal-http` Gateway (`gw-internal-http.yaml`), not `internal`. The HTTP and HTTPS listeners used to live on one `internal` Gateway, but Cilium's Gateway-API-to-Envoy translation leaks every app's exact-hostname HTTPS route into the HTTP listener's own route table too, and Envoy always prefers an exact hostname match over the redirect's wildcard `*` vhost - so the redirect never fired for any hostname that had its own route (see [cilium/cilium#44123](https://redirect.github.com/cilium/cilium/issues/44123) for the related upstream bug class). Splitting the HTTP listener into its own Gateway avoids the leak; the two Gateways share one LB IP via `io.cilium/lb-ipam-sharing-key`.

## DNS: HTTPRoutes CNAME to their own Gateway's hostname

Each Gateway carries two external-dns annotations (see `docs/architecture/network.md`'s DNS section for the full rationale): `external-dns.kubernetes.io/target` under `metadata.annotations` (read directly by external-dns's `gateway-httproute` source, makes every HTTPRoute attached to this Gateway resolve as a CNAME to this hostname instead of its own direct A record to the LB IP), and a matching `external-dns.kubernetes.io/hostname` under `spec.infrastructure.annotations` (propagated by Cilium to the Gateway's auto-created Service the same way `io.cilium/lb-ipam-ips` already is, so the `service` source creates the actual A record the CNAMEs point at). `internal` and `internal-http` share the same target/hostname value, since they already share one LB IP.

Both values are replaced per-env by `replace-domain`/`prefix-domain`'s own `gateway-external-dns-hostname.yaml` files, the same mechanism used for any HTTPRoute hostname.
