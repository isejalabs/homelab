---
status: current
---

# Troubleshooting: DNS resolution

For whoever's responding to a "this hostname won't resolve" or "this record is wrong" incident — not an introduction to the AdGuard → Unbound → PowerDNS chain (see [`architecture/network.md`](architecture/network.md) for that) and not the PowerDNS AXFR/TSIG operational mechanics (see [`k8s/apps/dns/powerdns/README.md`](../k8s/apps/dns/powerdns/README.md) for that — this doc links to it rather than repeating it).

A LAN client's query crosses, in order: **AdGuard** (filters, then forwards by domain) → **Unbound** (recursive resolution for the internal domain) → **PowerDNS** (authoritative for `<env>.iseja.net`, in progress) or the external root nameservers (`10.7.2.10`/`.12`, for the `iseja.net` root zone and anything else). The first job in any DNS incident is figuring out *which link in that chain* is actually wrong — a fix at the wrong layer won't help, and won't look like it failed either (DNS has no "it didn't work" signal beyond the wrong answer or no answer).

## 1. Isolate the layer by querying each resolver directly

Query each hop directly with `dig @<ip>`, bypassing everything upstream of it, rather than only testing from a LAN client (which always goes through the whole chain and can't tell you where it broke):

```sh
dig @<adguard-lb-ip> <hostname>       # what a real client actually gets
dig @<unbound-lb-ip> <hostname>       # skips AdGuard's filtering layer
dig @10.8.<env-id>.10 <hostname>      # skips straight to PowerDNS, for an in-cluster zone record
```

Per-environment LB IPs and the environment-ID table are in [`reference/environments.md`](reference/environments.md#environment-id) — don't hardcode them here, they're per-environment. `dig` directly at PowerDNS only makes sense for a name under `<env>.iseja.net` or its PTR zone; anything under the `iseja.net` root zone or a UCS-scoped subdomain (`dir.iseja.net`, `home.iseja.net`) is answered elsewhere in the chain per [`network.md`](architecture/network.md#dns-authoritative-zones-powerdns)'s zone table.

Narrow down from the result:

- **PowerDNS has the right record, Unbound doesn't return it** → Unbound's stub-zone config or AdGuard's forwarding rule is the problem, not PowerDNS itself.
- **PowerDNS itself has no record at all** → this is an external-dns registration gap, not a resolution-chain problem. Check that the owning `HTTPRoute`/`Service` actually carries the annotation external-dns needs (`external-dns.kubernetes.io/hostname`, or for a Gateway-attached route, the Gateway's own `target`/`hostname` annotations — see [`network.md`](architecture/network.md#dns-authoritative-zones-powerdns)), and that external-dns's own pod is actually running and reconciling (`kubectl logs -n <namespace> deploy/external-dns` — confirm the namespace via `kubectl get deploy -A | grep external-dns`, since it isn't fixed across environments the way PowerDNS's `powerdns` namespace is).

## 2. A record that resolves but is wrong (stale IP, wrong target)

Before treating this as a real bug, rule out the one already-known, harmless cause: external-dns's confirmed upstream churn bug (see [`network.md`](architecture/network.md#dns-authoritative-zones-powerdns)'s "Known upstream bug" paragraph, tracked at [kubernetes-sigs/external-dns#6555](https://redirect.github.com/kubernetes-sigs/external-dns/pull/6555) and this repo's [#1393](https://github.com/isejalabs/homelab/issues/1393)) — it removes and re-adds a record on every reconcile when more than one target shares an IP. The record stays *correct* at any point in time under this bug, it just churns; if `dig` shows the right answer when you happen to catch it, that's consistent with this known issue, not a real incident.

If the answer is actually wrong (not just churning), check in this order:

1. **Local caching** — AdGuard or the querying client's own resolver may be serving a cached answer from before a real change propagated. Query PowerDNS directly (step 1 above) to rule this out; if PowerDNS itself already has the right record, this is just a TTL/cache problem that resolves on its own.
2. **external-dns didn't update it yet** — check its reconcile interval and logs (each environment's own `FLUX_RECONCILIATION_INTERVAL`, per `network.md`) and whether the owning resource's annotation actually changed in git.

## 3. Secondary (`10.7.2.12`) out of sync with the primary

`10.7.2.12` is a TSIG-authenticated BIND9 slave of in-cluster PowerDNS (once delegated per environment) — see [`k8s/apps/dns/powerdns/README.md`](../k8s/apps/dns/powerdns/README.md#configuring-ns2-107212-bind9-as-a-tsig-authenticated-slave) for exactly how that's wired. To check whether a transfer actually happened, that doc's own cheat sheet already has the worked commands (checking BIND's logs for a `Transfer status: success` line, confirming the zone file materialized, then querying `10.7.2.12` directly) — don't duplicate them here, follow that doc's "Cheat sheet" section directly.

If a transfer is failing outright (not just stale), the most likely causes per that doc's own "Quirks encountered live" section are a `TSIG-ALLOW-AXFR` grant that got replaced instead of extended (it's full-replace, not additive) or a key mismatch between what PowerDNS has configured and what's in `/etc/bind/named.conf.local` on `10.7.2.12` itself.

## Verify the fix actually took

`dig` again from the actual layer a real LAN client uses first (`@<adguard-lb-ip>`), not just the layer you fixed — a correct answer at PowerDNS doesn't guarantee a client sees it yet if something upstream (Unbound's cache, AdGuard's own cache) is still holding a stale answer. If the client-facing query still looks wrong after the underlying record is confirmed correct, that's a caching/TTL wait, not a reason to keep changing the record.
