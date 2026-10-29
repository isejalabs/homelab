---
status: current
---

# Keycloak exposure and trust boundaries

How Keycloak can be reached, which request headers it trusts, and why there is no network policy around it yet. The review behind this page is [#1945](https://github.com/isejalabs/homelab/issues/1945), part of [#1937](https://github.com/isejalabs/homelab/issues/1937); the identity design is [ADR 0016](decisions/0016-identity-and-web-sso.md).

**On this page:** [Decisions](#decisions) · [Admin console on the issuer hostname](#admin-console-on-the-issuer-hostname) · [Trusted proxy headers](#trusted-proxy-headers) · [Network policies](#network-policies) · [Verified and not verified](#verified-and-not-verified)

## Decisions

| Question | Decision |
| --- | --- |
| `/admin` and `/realms/master` answer on the same hostname as the user-facing realms | Accepted, see [below](#admin-console-on-the-issuer-hostname) |
| Keycloak believes any `X-Forwarded-*` header that reaches it | Fixed at the route: the Gateway drops the client's `X-Forwarded-Host`, `-Port` and `-Prefix`, see [below](#trusted-proxy-headers) |
| No network policy around Keycloak and `keycloak-db` | Not restricted for Keycloak alone; decided together with the rest of the cluster in [#1995](https://github.com/isejalabs/homelab/issues/1995) |

## Admin console on the issuer hostname

The `HTTPRoute` [`http-route.yaml`](../k8s/apps/identity/keycloak/base/http-route.yaml) sends every path of the environment hostname to `keycloak-service:8080` on the `internal` Gateway, so the admin console (`/admin/`) and the `master` realm answer next to `iseja` and `admin`. Keycloak's reverse-proxy guide ([keycloak.org/server/reverseproxy](https://www.keycloak.org/server/reverseproxy)) lists `/admin/` and `/realms/master/` as internal-only paths that must not be exposed to the public internet, and `/metrics` and `/health` (management port 9000) as not exposed at all.

What this repository does about each:

- **No public exposure.** No route attaches to the `external` Gateway, and the `internal` Gateway's address is only advertised by BGP to the OPNsense pair. Which VLANs may reach it is a firewall rule outside this repository; from a LAN client the console answers (HTTP 200 on `/admin/master/console/` in `dev`, 2026-10-29).
- **The management port is not routed.** The route targets port 8080 only; port 9000 (`/metrics`, `/health`) has no route.
- **Why not split it.** The [break-glass login](keycloak-break-glass.md) and the Terragrunt provider ([`keycloak-realms.md`](keycloak-realms.md)) both use the console and the `master` realm on this hostname. A second hostname (`hostname-admin`) would not restrict anything by itself: Keycloak's hostname guide ([keycloak.org/server/hostname](https://www.keycloak.org/server/hostname)) states that the Admin REST API stays reachable on the normal hostname unless the proxy blocks it. A path match on the route that leaves `master` out would break both uses.

Accepted for that reason, with the exposure being exactly the reach of the `internal` Gateway. Revisit when a Keycloak route is ever attached to the `external` Gateway, or when the firewall lets VLANs reach `internal` that should not administer identity.

## Trusted proxy headers

[`keycloak.yaml`](../k8s/apps/identity/keycloak/base/keycloak.yaml) sets `proxy.headers: xforwarded` and no `proxy-trusted-addresses`. Keycloak's guide says that is only safe when the proxy overwrites the `X-Forwarded-*` headers and clients cannot reach Keycloak directly. With a bare `hostname` (as set here) the host is fixed, but scheme, port and path prefix are still taken from the headers; with a full URL (`https://…`) nothing is resolved dynamically from them.

Forged headers sent through the `internal` Gateway to the `dev` instance (2026-10-29, discovery document of `master`, `GET /realms/master/.well-known/openid-configuration`):

| Forged request header | Effect on `issuer` and endpoints |
| --- | --- |
| `X-Forwarded-Proto: http` | none, Envoy sets the header itself |
| `X-Forwarded-Host: evil.example` | none, the hostname is fixed by the `Keycloak` resource |
| `X-Forwarded-Port: 8443` | `https://<hostname>:8443/realms/master` |
| `X-Forwarded-Prefix: /evil` | `https://<hostname>/evil/realms/master` |

The same headers also changed a redirect (`GET /` answered `Location: https://<hostname>:8443/admin/`). So the Gateway did not overwrite `-Port` and `-Prefix`, and a client can choose the issuer and redirect URLs of its own response. No cache is configured in front of Keycloak in this repository, which limits this to the requester itself, but the issuer is what clients validate tokens against, so it is closed rather than accepted.

**Fix.** The Keycloak `HTTPRoute` removes `X-Forwarded-Host`, `X-Forwarded-Port` and `X-Forwarded-Prefix` from the request (`RequestHeaderModifier`), so only headers the proxy sets itself reach Keycloak. `X-Forwarded-Proto` and `X-Forwarded-For` stay: Envoy sets the first, and Keycloak needs the second for the client address. A full-URL `hostname` would be the Keycloak-side equivalent; it is not part of this change because the hostname is being reworked in [#1946](https://github.com/isejalabs/homelab/issues/1946).

Repeat the check with the forged headers after a change to the route, the Gateway or Cilium; the `issuer` must equal the baseline in every row:

```sh
host=dev-auth.dev.iseja.net
for h in 'X-Forwarded-Proto: http' 'X-Forwarded-Host: evil.example' 'X-Forwarded-Port: 8443' 'X-Forwarded-Prefix: /evil'; do
  curl -s -H "$h" "https://$host/realms/master/.well-known/openid-configuration" | jq -r '.issuer'
done
```

## Network policies

The repository has no `NetworkPolicy` or `CiliumNetworkPolicy` object, so Keycloak and `keycloak-db` accept connections from every pod. A policy for Keycloak alone is not added: the first policies of the repository set the pattern for all later ones (default deny or allow-list, how the Gateway's Envoy is selected, how Flux, probes and Longhorn keep working), which is a cluster-wide decision, tracked in [#1995](https://github.com/isejalabs/homelab/issues/1995).

The Keycloak part of that decision, as input: ingress to Keycloak from the Gateway only; ingress to `keycloak-db` from Keycloak and the dump and restore jobs only; egress from Keycloak to the UCS domain controllers (LDAPS) and from the dump job to RustFS.

## Verified and not verified

| Statement | State |
| --- | --- |
| Forged `X-Forwarded-Port` and `-Prefix` change the issuer and redirects; `-Host` and `-Proto` do not | Verified live in `dev`, 2026-10-29 |
| The admin console answers from a LAN client through the `internal` Gateway | Verified live in `dev`, 2026-10-29 |
| The route filter removes the forged headers | Not yet verified live; repeat the check above once the route reaches `dev` |
| A forged `X-Forwarded-For` reaches Keycloak as the client address (affects brute-force detection and event logs) | Not tested; Envoy appends to the header and Keycloak has no trusted-address list, so the leftmost, client-chosen value may win |
| Which VLANs can reach the `internal` Gateway | Not verified; set by the OPNsense firewall, outside this repository |
