# Networking

Four pieces work together to get a request from a LAN client to a pod: **Cilium** hands out and advertises
Service/Gateway IPs, **Gateway API** (implemented by Cilium) terminates TLS and routes by hostname,
**AdGuard + Unbound** resolve DNS for that hostname, and **unifi-controller** manages the physical network
hardware that Cilium's routes actually ride on. None of these are documented as one story anywhere else in
the repo — each app's own README is either a bare `kubectl` cheatsheet or nonexistent.

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
Cilium's BGP control plane has advertised that /32 from the worker nodes to the physical router
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
`10.8.<N>` block changes per environment.

**BGP** — not L2 announcements — is how those LB IPs actually become reachable from the LAN. Every
environment's [`CiliumBGPClusterConfig`](../../k8s/infra/kube-system/cilium/envs/prod/bgp-cluster-config.yaml)
peers from the worker nodes (control-plane nodes are explicitly excluded) to two fixed router addresses:

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
`gateway = "10.7.8.1"`). **Nothing in the repo names these two peers explicitly** — this is inferred, not
confirmed by a file — but they're almost certainly a redundant pair of routing instances on the physical
UniFi gateway/router, since that's the only router-layer device in this architecture and it's exactly the
hardware [`unifi-controller`](#unifi-controller-the-physical-network) manages.
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

`10.7.2.10`/`.12` aren't defined anywhere in `k8s/` — they're an authoritative source for the `iseja.net`
zone that lives on physical infrastructure outside this repo.

Both Services are `type: LoadBalancer` with `externalTrafficPolicy: Local` (preserves the client source IP —
relevant for AdGuard's per-client filtering rules) and a fixed `io.cilium/lb-ipam-ips` annotation per
environment. AdGuard's admin UI is a **separate** `ClusterIP` Service, reached only through the Gateway
(`adguard.<domain>` → `internal`), never through the DNS-serving LoadBalancer IP.

**Gap, not covered anywhere in the repo:** nothing here configures the LAN's DHCP server (or a router
setting) to actually hand out AdGuard's LB IP as clients' DNS server —
[`AdGuardHome.yaml`](../../k8s/apps/dns/adguard/base/config/AdGuardHome.yaml) even has `dhcp.enabled: false`,
confirming AdGuard doesn't hand out leases itself. That wiring has to happen manually in the router/UniFi
controller UI, outside Git.

## unifi-controller: the physical network

[`k8s/apps/network/unifi-controller/`](../../k8s/apps/network/unifi-controller/) runs the Ubiquiti UniFi
Network Controller in-cluster (its own MongoDB — see [`storage.md`](storage.md) for why that volume uses
proxmox-csi, not Longhorn). It's purely the **management/adoption plane** for the physical UniFi hardware —
access points, switches, and the router/gateway — not something k8s traffic flows through directly. Its
[README](../../k8s/apps/network/unifi-controller/README.md) is only a `kubectl` cheatsheet.

The actual link between "physical network" and "cluster networking" is the BGP peering described above: the
physical router (presumed to be the UniFi gateway hardware, based on unifi-controller being the only thing in
this repo that manages router-layer equipment — again, inferred, not named explicitly anywhere) is what
receives Cilium's route advertisements and is therefore what makes a LoadBalancer/Gateway IP reachable from
the rest of the LAN at all.

## What's not here

- **No documented DHCP→DNS wiring** (see above) — pointing LAN clients at AdGuard is a manual, outside-Git
  step.
- **No WAN-facing ingress path.** The `external` Gateway exists (and gets its own LB IP and cert), but no
  `HTTPRoute` in the repo attaches to it, and there's no Cloudflare Tunnel or other public-ingress mechanism
  anywhere in `k8s/`. Cloudflare's only confirmed role is DNS-01 certificate issuance. Whether `external`'s
  LB IP is NAT'd/port-forwarded to the internet at the router is a router-config question outside this repo
  either way.
- **ACME staging, not production** — the `ClusterIssuer` currently points at Let's Encrypt's staging
  endpoint, so certificates it issues won't be trusted by real browsers/clients until that's switched over.
