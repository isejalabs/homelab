# AdGuard Home

[AdGuard Home](https://github.com/AdguardTeam/AdGuardHome) is the LAN's DNS server with filtering and ad-blocking. Clients ask it; it answers blocked names itself, sends the internal domain to Unbound and everything else to Quad9 over DNS-over-HTTPS.

## At a glance

| | |
| --- | --- |
| Namespace | `adguard` |
| Runs in | `head`, `prod`, `qa`, `rebuild` (Flux set `optional`) |
| Installed via | Raw manifests (Deployment, two Services, HTTPRoute, SealedSecret), configuration from the ConfigMap generated from [`base/config/AdGuardHome.yaml`](base/config/AdGuardHome.yaml) |
| Flux Kustomization | `adguard`, depends on `cilium`, `gateway-api`, `sealed-secrets` |

## Purpose

The resolver that LAN clients actually use, so filtering lists and per-client rules live in one place. It does not serve DHCP (`dhcp.enabled: false`); the UCS servers do. How it fits with Unbound, PowerDNS and the physical network: [`network.md`](../../../../docs/architecture/network.md#dns-adguard--unbound).

## Where it is used

- **Used by**: LAN clients, as their DNS server (which address DHCP hands out is set on the UCS side, outside this repo).
- **Depends on**:
  - [`unbound`](../unbound/README.md) as upstream for `iseja.net` and the reverse zones, queried in parallel with the resolver VIP `10.9.9.9` on the OPNsense pair (`upstream_mode: parallel`, so one of the two being down does not stall);
  - Quad9 (`dns10.quad9.net`) over DoH for everything else;
  - `cilium` for the load balancer address, the `internal` Gateway for the UI.

## Access

Two separate Services: DNS on a load balancer address, the admin UI only through the Gateway.

| env | DNS (port 53) | Admin UI |
| --- | --- | --- |
| `head` | `10.8.1.53` | `https://head-adguard.head.iseja.net` |
| `qa` | `10.8.2.53` | `https://qa-adguard.qa.iseja.net` |
| `rebuild` | `10.8.7.53` | `https://rebuild-adguard.rebuild.iseja.net` |
| `prod` | `10.8.8.53` | `https://adguard.prod.iseja.net` |

The DNS Service also gets the record `adguard-lb.<env>.iseja.net` (with the prefix, `qa-adguard-lb.qa.iseja.net`); the bare name belongs to the UI route. Both Services use `externalTrafficPolicy: Local` so per-client rules see the real client address. The UI login is the `users` SealedSecret (see the cheat sheet to change it). The hostname scheme: [`reference/environments.md`](../../../../docs/reference/environments.md#domain-and-naming).

## Updates

- **Image**: `docker.io/adguard/adguardhome` with tag and digest in [`base/deployment.yaml`](base/deployment.yaml); the two helper init containers use a digest-pinned `busybox`.
- No special Renovate rule: the default flow of [`update-handling.md`](../../../../docs/operations/update-handling.md) applies to all environments.

## Operations

| Task | Doc |
| --- | --- |
| AdGuard stalls or logs `operation not permitted` while Unbound is down | [`troubleshooting-dns.md`](../../../../docs/troubleshooting/troubleshooting-dns.md#6-adguard-stalls-or-logs-operation-not-permitted-while-unbound-is-down) |
| A record that resolves wrongly, layer-by-layer isolation | [`troubleshooting-dns.md`](../../../../docs/troubleshooting/troubleshooting-dns.md#1-isolate-the-layer-by-querying-each-resolver-directly) |

## Cheat sheet

Replace `<env>` with `head`, `qa`, `rebuild` or `prod`.

```sh
flux get ks adguard --context admin@<env>-homelab
kubectl get pods,svc,httproute -n adguard --context admin@<env>-homelab
kubectl logs -n adguard deploy/adguard -f --context admin@<env>-homelab

# does it answer, and from which upstream? (address from the table above)
dig @10.8.<env-id>.53 example.org +short
dig @10.8.<env-id>.53 qa-adguard.qa.iseja.net +short
```

Change the UI users: edit the plain `users.yaml` locally (never commit it), then seal it into [`base/secret-users.yaml`](base/secret-users.yaml) with the certificate of the environment's cluster. The `SealedSecret` is namespace-scoped, so the namespace is `adguard`:

```sh
cat k8s/apps/dns/adguard/base/users.yaml | \
  kubectl create secret generic users --dry-run=client --from-file=users.yaml=/dev/stdin -o yaml | \
  kubeseal --cert terragrunt/non-prod/eu-central-1/dev/vehagn-k8s/assets/sealed-secrets/certificate/sealed-secrets.cert -o yaml -n adguard --merge-into k8s/apps/dns/adguard/base/secret-users.yaml
```

## Upstream

- Source and documentation: <https://github.com/AdguardTeam/AdGuardHome>, <https://adguard-dns.io/kb/adguard-home/overview/>
- Releases: <https://github.com/AdguardTeam/AdGuardHome/releases>
