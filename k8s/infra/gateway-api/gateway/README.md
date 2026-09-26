See [`docs/architecture/network.md`](../../../../docs/architecture/network.md) for how this Gateway setup
fits into the overall networking story (LB IPAM, DNS, the physical network).

`http-route-redirect.yaml`'s `http-redirect-to-https` `HTTPRoute` has no `hostname` specification (it matches all hosts), so the domain-replacement/prefix components reject it by name to avoid a zero-match hard error - see `components/transformers/replace-domain/repl/httproute-replace-domain.yaml` and `components/transformers/prefix-domain/repl/httproute-prefix-domain.yaml`.

The route attaches to the `internal-http` Gateway (`gw-internal-http.yaml`), not `internal`. The HTTP and HTTPS listeners used to live on one `internal` Gateway, but Cilium's Gateway-API-to-Envoy translation leaks every app's exact-hostname HTTPS route into the HTTP listener's own route table too, and Envoy always prefers an exact hostname match over the redirect's wildcard `*` vhost - so the redirect never fired for any hostname that had its own route (see [cilium/cilium#44123](https://redirect.github.com/cilium/cilium/issues/44123) for the related upstream bug class). Splitting the HTTP listener into its own Gateway avoids the leak; the two Gateways share one LB IP via `io.cilium/lb-ipam-sharing-key`.

## DNS: HTTPRoutes CNAME to their own Gateway's hostname

Each Gateway carries two external-dns annotations (see `docs/architecture/network.md`'s DNS section for the full rationale): `external-dns.kubernetes.io/target` under `metadata.annotations` (read directly by external-dns's `gateway-httproute` source, makes every HTTPRoute attached to this Gateway resolve as a CNAME to this hostname instead of its own direct A record to the LB IP), and a matching `external-dns.kubernetes.io/hostname` under `spec.infrastructure.annotations` (propagated by Cilium to the Gateway's auto-created Service the same way `io.cilium/lb-ipam-ips` already is, so the `service` source creates the actual A record the CNAMEs point at). `internal` and `internal-http` share the same target/hostname value, since they already share one LB IP.

Both values are replaced per-env by `replace-domain`/`prefix-domain`'s own `gateway-external-dns-hostname.yaml` files, the same mechanism used for any HTTPRoute hostname.
