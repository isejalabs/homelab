# external-dns

[external-dns](https://github.com/kubernetes-sigs/external-dns) publishes DNS records for the cluster's `HTTPRoute`s, Gateways and `LoadBalancer` Services. Here it writes them into the environment's own [PowerDNS](../../../apps/dns/powerdns/README.md) zone over RFC2136, signed with a TSIG key.

## At a glance

| | |
| --- | --- |
| Namespace | `external-dns` |
| Runs in | all 8 environments (Flux set `minimal`) |
| Installed via | HelmRelease, chart `external-dns` from the `kubernetes-sigs.github.io/external-dns` Helm repository, plus an `ExternalSecret` for the TSIG key |
| Flux Kustomization | `external-dns`, depends on `gateway-api-crds`, `infra-ns` |

## Purpose

An app is reachable by name as soon as its route exists, without anyone editing a zone. It creates A records for load balancer addresses, CNAMEs from each `HTTPRoute` to its Gateway's name, and PTR records for the environment's `10.8.<env-id>.0/24` range (`--policy` syncs, so removed resources lose their records). The mechanism and the reasoning: [`network.md`](../../../../docs/architecture/network.md#dns-authoritative-zones-powerdns), [ADR 0011](../../../../docs/decisions/0011-powerdns-as-dns-server.md).

## Where it is used

- **Used by**: every name under `<env>.iseja.net` that an app, Gateway or Service announces; AdGuard, Unbound and the clients then resolve them. A hostname annotation or an `HTTPRoute` is all an app has to provide.
- **Depends on**: [`powerdns`](../../../apps/dns/powerdns/README.md) (service `powerdns.powerdns.svc.cluster.local:53`), the TSIG key `dynupdate` (the Secret `powerdns-tsig-dynupdate`, from the 1Password item `powerdns-tsig-dynupdate#<env>` via External Secrets), and the Gateway API CRDs for the `gateway-httproute` source.

## Access

Not exposed. It only talks to PowerDNS and the Kubernetes API.

## Updates

- **Chart**: `spec.chart.spec.version` in [`base/helmrelease.yaml`](base/helmrelease.yaml). No special Renovate rule: the default flow of [`update-handling.md`](../../../../docs/operations/update-handling.md) applies.
- **Known upstream bug**: PTR and CNAME records are removed and re-added on every reconcile (harmless but noisy); `interval` is therefore fixed at `10m` in all environments. Tracked in [#1393](https://github.com/isejalabs/homelab/issues/1393), upstream [kubernetes-sigs/external-dns#6555](https://redirect.github.com/kubernetes-sigs/external-dns/issues/6555). Revisit when the fix ships.

## Operations

| Task | Doc |
| --- | --- |
| A record is missing, stale or wrong | [`troubleshooting-dns.md`](../../../../docs/troubleshooting/troubleshooting-dns.md#2-a-record-that-resolves-but-is-wrong-stale-ip-wrong-target) |
| Zones, PTR zones, TSIG keys | [`powerdns` README](../../../apps/dns/powerdns/README.md), [`network.md`](../../../../docs/architecture/network.md#dns-authoritative-zones-powerdns) |

## Cheat sheet

Replace `<env>` with the environment.

```sh
flux get ks external-dns --context admin@<env>-homelab
kubectl get pods -n external-dns --context admin@<env>-homelab
kubectl logs -n external-dns deploy/external-dns -f --context admin@<env>-homelab

# does the record exist in PowerDNS? (the zone's primary, address from the PowerDNS README)
dig @10.8.<env-id>.10 <env>-whoami.<env>.iseja.net +short

# the zone as PowerDNS has it
kubectl exec -n powerdns deploy/powerdns --context admin@<env>-homelab -- pdnsutil zone list <env>.iseja.net
```

## Upstream

- Source and releases: <https://github.com/kubernetes-sigs/external-dns>
- RFC2136 provider: <https://kubernetes-sigs.github.io/external-dns/latest/docs/tutorials/rfc2136/>
