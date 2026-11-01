# whoami

Traefik's [`whoami`](https://github.com/traefik/whoami) is a tiny HTTP server that echoes what it receives (headers, client address, hostname). It is the test target for the Gateway, DNS and load balancer path.

## At a glance

| | |
| --- | --- |
| Namespace | `whoami` |
| Runs in | all 8 environments (Flux set `minimal`) |
| Installed via | Raw manifests (Deployment, Service, a second `LoadBalancer` Service, `HTTPRoute`) |
| Flux Kustomization | `whoami`, depends on `cilium` |

## Purpose

A known-good backend to prove that a new environment or a change in the network stack works, with no state and no credentials: does the `internal` Gateway route by hostname, does the wildcard certificate match, does external-dns publish the name, does a load balancer address get advertised. The echoed headers also show what a proxy hop adds (for example `X-Forwarded-*`).

## Where it is used

- **Used by**: nobody; it exists to be queried by hand and by smoke tests.
- **Depends on**: `cilium` (Gateway API and load balancer), cert-manager and external-dns indirectly through the Gateway.

## Access

Three names for the same app, each exercising a different path. The HTTPS names go through the `internal` Gateway; the `-lb` name is a `LoadBalancer` Service on port 80 (plain HTTP), `externalTrafficPolicy: Local`.

| env | Gateway (HTTPS) | Load balancer (HTTP) |
| --- | --- | --- |
| `dbg` | `https://dbg-whoami.dbg.iseja.net` | `http://dbg-whoami-lb.dbg.iseja.net`, `10.8.9.87` |
| `dev` | `https://dev-whoami.dev.iseja.net` | `http://dev-whoami-lb.dev.iseja.net`, `10.8.3.87` |
| `head` | `https://head-whoami.head.iseja.net` | `http://head-whoami-lb.head.iseja.net`, `10.8.1.87` |
| `poc` | `https://poc-whoami.poc.iseja.net` | `http://poc-whoami-lb.poc.iseja.net`, `10.8.6.87` |
| `prod` | `https://whoami.prod.iseja.net` | `http://whoami-lb.prod.iseja.net`, `10.8.8.87` |
| `qa` | `https://qa-whoami.qa.iseja.net` | `http://qa-whoami-lb.qa.iseja.net`, `10.8.2.87` |
| `rebuild` | `https://rebuild-whoami.rebuild.iseja.net` | `http://rebuild-whoami-lb.rebuild.iseja.net`, `10.8.7.87` |
| `src` | `https://src-whoami.src.iseja.net` | `http://src-whoami-lb.src.iseja.net`, `10.8.5.87` |

`whoami-ingress.<env>.iseja.net` (prefixed likewise) is a second name on the same route. The `-lb` suffix exists because the bare name is taken by the route's CNAME and DNS forbids a CNAME next to another record at the same name ([`network.md`](../../../../docs/architecture/network.md#dns-authoritative-zones-powerdns)). Hostname scheme: [`reference/environments.md`](../../../../docs/reference/environments.md#domain-and-naming).

## Updates

- **Image**: `ghcr.io/traefik/whoami` with tag and digest in [`base/deployment.yaml`](base/deployment.yaml). No special Renovate rule: the default flow of [`update-handling.md`](../../../../docs/operations/update-handling.md) applies.

## Operations

Nothing specific. Name or routing problems: [`troubleshooting-dns.md`](../../../../docs/troubleshooting/troubleshooting-dns.md).

## Cheat sheet

```sh
flux get ks whoami --context admin@<env>-homelab
kubectl get pods,svc,httproute -n whoami --context admin@<env>-homelab

# through the Gateway, then straight to the load balancer
curl -s https://<env>-whoami.<env>.iseja.net
curl -s http://10.8.<env-id>.87

# is the name published? (PowerDNS of the environment)
dig @10.8.<env-id>.10 <env>-whoami.<env>.iseja.net +short
```

## Upstream

- Source and releases: <https://github.com/traefik/whoami>
