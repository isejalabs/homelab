# Networking

A request from a LAN client to a pod crosses pieces this repo manages and pieces it doesn't. In-cluster:
**Cilium** hands out and BGP-advertises Service/Gateway IPs, **Gateway API** (implemented by Cilium)
terminates TLS and routes by hostname, **AdGuard + Unbound** resolve DNS, and **unifi-controller** is only the
management UI for the WiFi access points and switches. Outside the cluster and outside this repo entirely:
an **OPNsense** HA firewall/router pair is what Cilium's BGP sessions actually peer with, a redundant pair of
**UCS (Univention Corporate Server)** machines provide DHCP (reached via DHCP relay on the OPNsense boxes),
identity services (Kerberos, LDAP, Active Directory), and DNS for a couple of subdomains, and a separate pair
of small Debian LXCs are the actual root nameservers for the whole `iseja.net` zone. None of this is
documented as one story anywhere else in the repo — each in-cluster app's own README is either a bare
`kubectl` cheatsheet or nonexistent, and the physical-network side isn't in Git at all.

## End-to-end flow

```
LAN client
   │  DNS query, e.g. adguard.prod.iseja.net
   ▼
AdGuard  (LoadBalancer Service, e.g. 10.8.8.53)
   │  filtering/ad-block, then forwards by domain:
   │    - "iseja.net" / reverse-DNS → Unbound
   │    - everything else           → Quad9 (public DoH)
   ▼
Unbound  (LoadBalancer Service, e.g. 10.8.8.8 + 10.8.8.11)
   │  recursive/validating resolution for the internal domain
   ▼
AdGuard returns the resolved IP — the Gateway's LB IP (e.g. 10.8.8.80 internal / 10.8.8.83 external)
   ▼
Cilium's BGP control plane has advertised that /32 from the worker nodes to the OPNsense HA pair
   ▼
Cilium-implemented Gateway API Gateway — TLS terminated (cert-manager-issued cert), HTTPRoute hostname match
   ▼
Kubernetes Service → Pod
```

## Cilium: LB IPAM and BGP route advertisement

[`k8s/infra/kube-system/cilium/base/values.yaml`](../../k8s/infra/kube-system/cilium/base/values.yaml) turns
on the two Cilium features everything else here depends on:

```yaml
ipam:
  mode: kubernetes   # pod IPAM — separate from LB-IPAM below
gatewayAPI:
  enabled: true
bgpControlPlane:
  enabled: true
```

**LB IPAM** — each environment gets its own `/24`-ish block via a
[`CiliumLoadBalancerIPPool`](../../k8s/infra/kube-system/cilium/envs/) named `bgp-pool`, e.g.
[`envs/prod/ip-pool-bgp.yaml`](../../k8s/infra/kube-system/cilium/envs/prod/ip-pool-bgp.yaml):

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: bgp-pool
spec:
  blocks:
    - start: 10.8.8.8
      stop: 10.8.8.250
```

Every `LoadBalancer` Service or Gateway requests a specific address from that pool with the
`io.cilium/lb-ipam-ips` annotation — see [`kustomize.md`](kustomize.md) for how a `base/` placeholder IP
(e.g. `192.168.1.253`) gets patched to the real per-env address (e.g. `10.8.8.53`) via `envs/<env>/`
overlays. Offsets are kept stable across environments so the same app always lands on the same last octet
(e.g. `.8`/`.11` = unbound, `.53` = adguard, `.80` = internal gateway, `.83` = external gateway) — only the
`10.8.<N>` block changes per environment. The full set of per-environment pools
([`k8s/infra/kube-system/cilium/envs/<env>/ip-pool-bgp.yaml`](../../k8s/infra/kube-system/cilium/envs/)):

| env | pool |
| --- | --- |
| `head` | `10.8.1.0/24` |
| `qa` | `10.8.2.0/24` |
| `dev` | `10.8.3.0/24` |
| `src` | `10.8.5.0/24` |
| `poc` | `10.8.6.0/24` |
| `rebuild` | `10.8.7.0/24` |
| `prod` | `10.8.8.0/24` |
| `dbg` | `10.8.9.0/24` |

(each pool's actual `CiliumLoadBalancerIPPool` block only spans `.8`–`.250` of its `/24`, leaving the low and
high ends free for infrastructure/reservations.)

**BGP** — not L2 announcements — is how those LB IPs actually become reachable from the rest of the network,
and the choice matters here for a specific reason: the `10.8.0.0/16` range those pools carve `/24`s out of
(informally "the Kubernetes BGP net") is a completely different subnet from `10.7.8.0/24`, the one the Talos
nodes' own network interfaces actually sit in — a VLAN dedicated solely to cluster nodes, isolated from every
other VLAN/net on the network (DMZ, LAN, other servers, ...). No node has an interface anywhere in
`10.8.0.0/16` at all. L2 announcement (Cilium's other LB-IP mechanism, gratuitous-ARP-based) requires the
advertised IP to sit in the *same* L2 segment as the node advertising it — it couldn't work across that
subnet boundary. BGP has no such requirement: it's a routing-layer (L3) protocol, so any node can advertise a
route for any `10.8.x.x/32` IP regardless of what subnet its own interface lives in, and the router (OPNsense,
below) just adds that route to its table like any other. That's what makes the LB-IP address space fully
independent of node placement — an IP can be reassigned to any node, or advertised redundantly from several,
without needing any node to actually hold it as a local address.

Every environment's
[`CiliumBGPClusterConfig`](../../k8s/infra/kube-system/cilium/envs/prod/bgp-cluster-config.yaml) peers from
the worker nodes (control-plane nodes are explicitly excluded) to two fixed router addresses:

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: cilium-bgp
spec:
  nodeSelector:
    matchExpressions:
      - key: node-role.kubernetes.io/control-plane
        operator: DoesNotExist
  bgpInstances:
    - name: "instance-64528"
      localASN: 64528
      peers:
        - peerASN: 64520
          peerAddress: 10.7.8.2
        - peerASN: 64520
          peerAddress: 10.7.8.3
```

`10.7.8.2`/`10.7.8.3` sit on the same subnet (VLAN, `10.7.8.0/24`) the Talos nodes themselves live on
(confirmed per-environment in `terragrunt/<tier>/eu-central-1/<env>/vehagn-k8s/terragrunt.hcl`, e.g.
`gateway = "10.7.8.1"`). These two addresses are **not** documented in this repo — they're a pair of
[OPNsense](https://opnsense.org/) firewalls/routers running in an HA setup (physical infrastructure entirely
outside Git); `10.7.8.1` is the standard/virtual gateway IP that VMs and nodes actually route through
day-to-day, while `.2`/`.3` are the individual OPNsense boxes' own addresses, each peering BGP independently
so a route stays advertised even if one box is down.
[`bgp-advertisement.yaml`](../../k8s/infra/kube-system/cilium/base/bgp-advertisement.yaml) advertises every
`LoadBalancerIP` (Service and Gateway alike) into that BGP session, and
[`k8s/infra/kube-system/cilium/README.md`](../../k8s/infra/kube-system/cilium/README.md) has captured
`cilium bgp peers`/`cilium bgp routes` output confirming this is live in practice — nodes peer successfully
and advertise routes like `10.8.8.80/32`.

## Gateway API: Cilium as the implementation

No `GatewayClass` resource exists in the repo — `gatewayAPI.enabled: true` makes the Cilium operator create
one automatically (`gatewayClassName: cilium` on every `Gateway`).
[`k8s/infra/gateway-api/gateway/base/`](../../k8s/infra/gateway-api/gateway/base/) defines three:

| Gateway | Listener | LB IP (prod) | Purpose |
| --- | --- | --- | --- |
| `internal` | HTTPS:443 | `10.8.8.80` (shared) | main entry point for every app's `HTTPRoute` |
| `internal-http` | HTTP:80 | `10.8.8.80` (shared) | HTTP→HTTPS redirect only |
| `external` | HTTPS:443 | `10.8.8.83` | reserved for public-facing routes (see [gap](#whats-not-here) below) |

`internal` and `internal-http` deliberately **share one LB IP** via `io.cilium/lb-ipam-sharing-key`, split
into two separate `Gateway` objects instead of one Gateway with two listeners —
[`k8s/infra/gateway-api/gateway/README.md`](../../k8s/infra/gateway-api/gateway/README.md) explains why:
Cilium's Gateway-API-to-Envoy translation leaks every app's exact-hostname HTTPS route into the HTTP
listener's own route table too, and Envoy always prefers an exact-hostname match over the redirect's
wildcard vhost — so a same-Gateway HTTP→HTTPS redirect silently stopped firing for any hostname that had its
own route (tracked upstream as [cilium/cilium#44123](https://github.com/cilium/cilium/issues/44123)).
Splitting the listeners into two Gateways avoids the route leak entirely, at the cost of `internal-http`
restricting `allowedRoutes` to `from: Same` so only its own redirect route can attach.

Apps attach an `HTTPRoute` to `internal` by `parentRefs`, e.g.
[`k8s/apps/dns/adguard/base/http-route.yaml`](../../k8s/apps/dns/adguard/base/http-route.yaml) (already
covered in [`kustomize.md`](kustomize.md) as the domain-templating example) — the same pattern repeats for
`whoami`, `checkmk-agent`, `longhorn-core`'s UI, `flux-operator`'s UI, and `actualbudget`. No app in the repo
currently attaches an `HTTPRoute` to `external`.

**TLS** is one wildcard `Certificate` per Gateway, not per app —
[`k8s/infra/gateway-api/gateway/base/cert.yaml`](../../k8s/infra/gateway-api/gateway/base/cert.yaml) issues
`*.example.com` (templated to the real per-env domain), referenced by both `internal` and `external`'s
`tls.certificateRefs`. The issuer
([`k8s/infra/cert-manager/cert-manager/base/cluster-issuer.yaml`](../../k8s/infra/cert-manager/cert-manager/base/cluster-issuer.yaml))
solves ACME DNS-01 via Cloudflare (currently pointed at **Let's Encrypt staging**, not production — worth
noticing before relying on the resulting cert being trusted by real clients):

```yaml
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org./directory
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef: {name: cloudflare-api-token, key: api-token}
```

The Cloudflare API token itself is a `SealedSecret` — see [`secrets.md`](secrets.md#sealed-secrets--for-secrets-committed-as-ciphertext)
for how it got there. This is Cloudflare's **only** role in this architecture: issuing certificates. There is
no Cloudflare Tunnel or other public-ingress path anywhere in `k8s/` — see the gap noted below.

## DNS: AdGuard + Unbound

These are two separate apps, not a sidecar pair —
[`k8s/apps/dns/adguard/`](../../k8s/apps/dns/adguard/) and
[`k8s/apps/dns/unbound/`](../../k8s/apps/dns/unbound/) each have their own Deployment and `LoadBalancer`
Service. AdGuard is the LAN's actual DNS server (filtering/ad-blocking); Unbound is its upstream resolver for
anything under the internal domain —
[`k8s/apps/dns/adguard/base/config/AdGuardHome.yaml`](../../k8s/apps/dns/adguard/base/config/AdGuardHome.yaml):

```yaml
upstream_dns:
  - https://dns10.quad9.net/dns-query
  - "[/iseja.net/]10.8.8.8 10.9.9.9"
  - "[/10.in-addr.arpa/]10.8.8.8 10.9.9.9"
```

`10.8.8.8` is Unbound's own prod LB IP — so AdGuard forwards `iseja.net` (and reverse-DNS) queries
specifically to Unbound, and everything else to Quad9 over DoH. Unbound itself is configured as a validating
recursive resolver with a stub-zone for the real domain
([`k8s/apps/dns/unbound/base/config/zones.d/unbound-iseja.conf`](../../k8s/apps/dns/unbound/base/config/zones.d/unbound-iseja.conf)):

```
stub-zone:
    name: "iseja.net."
    stub-addr: 10.7.2.10
    stub-addr: 10.7.2.12
```

`10.7.2.10`/`.12` aren't defined anywhere in `k8s/` — they're a pair of small Debian LXC containers acting as
the root/authoritative nameservers for the `iseja.net` zone (see
[below](#physical-network-opnsense-ucs-and-the-root-nameservers)), not UCS: UCS's own DNS role is scoped to
the `dir.iseja.net`/`home.iseja.net` subdomains, not the root zone.

Both Services are `type: LoadBalancer` with `externalTrafficPolicy: Local` (preserves the client source IP —
relevant for AdGuard's per-client filtering rules) and a fixed `io.cilium/lb-ipam-ips` annotation per
environment. AdGuard's admin UI is a **separate** `ClusterIP` Service, reached only through the Gateway
(`adguard.<domain>` → `internal`), never through the DNS-serving LoadBalancer IP.
[`AdGuardHome.yaml`](../../k8s/apps/dns/adguard/base/config/AdGuardHome.yaml) has `dhcp.enabled: false` —
AdGuard doesn't hand out DHCP leases itself; that's UCS's job (below). Whether DHCP actually advertises
AdGuard's LB IP as clients' DNS server is a UCS-side config question, outside this repo either way.

## Physical network: OPNsense, UCS, and the root nameservers

Everything in this section is physical infrastructure with no representation in this repo at all — it's
documented here only because Cilium's BGP config and Unbound's stub-zone both reference it by IP. Almost all
of it (per its owner) is itself a future migration candidate into Kubernetes, same as everything else in this
homelab.

**OPNsense** — a pair of [OPNsense](https://opnsense.org/) firewalls/routers in an HA configuration is the
network's routing layer: `10.7.8.1` is the standard/virtual gateway IP everything else routes through, while
`10.7.8.2`/`.3` are the two boxes' individual addresses, each independently peering BGP with the cluster's
worker nodes (see [above](#cilium-lb-ipam-and-bgp-route-advertisement)) so LoadBalancer/Gateway routes stay
advertised even if one box is down.

**UCS (Univention Corporate Server)** — a redundant pair of UCS machines (`10.7.2.10`/`.12` are *not* these —
see below) provide DHCP and identity management (Kerberos, LDAP, and Active Directory — UCS bundles a
Samba/AD-compatible domain controller) for the network, plus DNS scoped specifically to the
`dir.iseja.net`/`home.iseja.net` subdomains (not the `iseja.net` root zone itself). Being on their own VLAN,
DHCP requests from client VLANs reach UCS via the **DHCP relay** service running on the OPNsense boxes —
clients broadcast on their local segment, OPNsense relays the request across to UCS's VLAN, and the response
is relayed back.

**The `iseja.net` root nameservers** (`10.7.2.10`/`.12`, referenced by Unbound's stub-zone above) are a
*separate* pair of machines from UCS — small Debian LXC containers, authoritative for the `iseja.net` zone
itself, distinct from UCS's subdomain-scoped DNS role. Not yet migrated into Kubernetes.

**unifi-controller** ([`k8s/apps/network/unifi-controller/`](../../k8s/apps/network/unifi-controller/), its
own MongoDB via proxmox-csi — see [`storage.md`](storage.md)) is unrelated to any of the above: it's only the
management/adoption UI for the physical WiFi access points and switches, not something k8s traffic flows
through, and not a BGP peer, DHCP/identity provider, or nameserver. Its
[README](../../k8s/apps/network/unifi-controller/README.md) is only a `kubectl` cheatsheet.

## What's not here

- **No WAN-facing ingress path.** The `external` Gateway exists (and gets its own LB IP and cert), but no
  `HTTPRoute` in the repo attaches to it, and there's no Cloudflare Tunnel or other public-ingress mechanism
  anywhere in `k8s/`. Cloudflare's only confirmed role is DNS-01 certificate issuance. Whether `external`'s
  LB IP is NAT'd/port-forwarded to the internet at OPNsense is a router-config question outside this repo
  either way.
- **ACME staging, not production** — the `ClusterIssuer` currently points at Let's Encrypt's staging
  endpoint, so certificates it issues won't be trusted by real browsers/clients until that's switched over.
- **The physical network itself (OPNsense, UCS, the root nameservers) isn't in Git** — everything in the
  section above is documented from IP references found in-cluster, not from any config this repo actually
  owns, and most of it is itself a future Kubernetes-migration candidate.
