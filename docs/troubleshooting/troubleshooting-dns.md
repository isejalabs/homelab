---
status: current
---

# Troubleshooting: DNS resolution

For whoever's responding to a "this hostname won't resolve" or "this record is wrong" incident — not an introduction to the AdGuard → Unbound → PowerDNS chain (see [`architecture/network.md`](../architecture/network.md) for that) and not the PowerDNS AXFR/TSIG operational mechanics (see [`k8s/apps/dns/powerdns/README.md`](../../k8s/apps/dns/powerdns/README.md) for that — this doc links to it rather than repeating it).

A LAN client's query crosses, in order: **AdGuard** (filters, then forwards by domain) → **Unbound** (recursive resolution for the internal domain) → **PowerDNS** (authoritative for `<env>.iseja.net`, in progress) or the external root nameservers (`10.7.2.10`/`.12`, for the `iseja.net` root zone and anything else). The first job in any DNS incident is figuring out *which link in that chain* is actually wrong — a fix at the wrong layer won't help, and won't look like it failed either (DNS has no "it didn't work" signal beyond the wrong answer or no answer).

## 1. Isolate the layer by querying each resolver directly

Query each hop directly with `dig @<ip>`, bypassing everything upstream of it, rather than only testing from a LAN client (which always goes through the whole chain and can't tell you where it broke):

```sh
dig @<adguard-lb-ip> <hostname>       # what a real client actually gets
dig @<unbound-lb-ip> <hostname>       # skips AdGuard's filtering layer
dig @10.8.<env-id>.10 <hostname>      # skips straight to PowerDNS, for an in-cluster zone record
```

Per-environment LB IPs and the environment-ID table are in [`reference/environments.md`](../reference/environments.md#environment-id) — don't hardcode them here, they're per-environment. `dig` directly at PowerDNS only makes sense for a name under `<env>.iseja.net` or its PTR zone; anything under the `iseja.net` root zone or a UCS-scoped subdomain (`dir.iseja.net`, `home.iseja.net`) is answered elsewhere in the chain per [`network.md`](../architecture/network.md#dns-authoritative-zones-powerdns)'s zone table.

Narrow down from the result:

- **PowerDNS has the right record, Unbound doesn't return it** → Unbound's stub-zone config or AdGuard's forwarding rule is the problem, not PowerDNS itself.
- **PowerDNS itself has no record at all** → this is an external-dns registration gap, not a resolution-chain problem. Check that the owning `HTTPRoute`/`Service` actually carries the annotation external-dns needs (`external-dns.kubernetes.io/hostname`, or for a Gateway-attached route, the Gateway's own `target`/`hostname` annotations — see [`network.md`](../architecture/network.md#dns-authoritative-zones-powerdns)), and that external-dns's own pod is actually running and reconciling (`kubectl logs -n <namespace> deploy/external-dns` — confirm the namespace via `kubectl get deploy -A | grep external-dns`, since it isn't fixed across environments the way PowerDNS's `powerdns` namespace is).

## 2. A record that resolves but is wrong (stale IP, wrong target)

Before treating this as a real bug, rule out the one already-known, harmless cause: external-dns's confirmed upstream churn bug (see [`network.md`](../architecture/network.md#dns-authoritative-zones-powerdns)'s "Known upstream bug" paragraph, tracked at [kubernetes-sigs/external-dns#6555](https://redirect.github.com/kubernetes-sigs/external-dns/pull/6555) and this repo's [#1393](https://github.com/isejalabs/homelab/issues/1393)) — it removes and re-adds a record on every reconcile when more than one target shares an IP. The record stays *correct* at any point in time under this bug, it just churns; if `dig` shows the right answer when you happen to catch it, that's consistent with this known issue, not a real incident.

If the answer is actually wrong (not just churning), check in this order:

1. **Local caching** — AdGuard or the querying client's own resolver may be serving a cached answer from before a real change propagated. Query PowerDNS directly (step 1 above) to rule this out; if PowerDNS itself already has the right record, this is just a TTL/cache problem that resolves on its own.
2. **external-dns didn't update it yet** — check its reconcile interval and logs (each environment's own `FLUX_RECONCILIATION_INTERVAL`, per `network.md`) and whether the owning resource's annotation actually changed in git.

## 3. Secondary (`10.7.2.12`) out of sync with the primary

`10.7.2.12` is a TSIG-authenticated BIND9 slave of in-cluster PowerDNS (once delegated per environment) — see [`k8s/apps/dns/powerdns/README.md`](../../k8s/apps/dns/powerdns/README.md#configuring-ns2-107212-bind9-as-a-tsig-authenticated-slave) for exactly how that's wired. To check whether a transfer actually happened, that doc's own cheat sheet already has the worked commands (checking BIND's logs for a `Transfer status: success` line, confirming the zone file materialized, then querying `10.7.2.12` directly) — don't duplicate them here, follow that doc's "Cheat sheet" section directly.

If a transfer is failing outright (not just stale), the most likely causes per that doc's own "Quirks encountered live" section are a `TSIG-ALLOW-AXFR` grant that got replaced instead of extended (it's full-replace, not additive) or a key mismatch between what PowerDNS has configured and what's in `/etc/bind/named.conf.local` on `10.7.2.12` itself.

## 4. Unbound restarts (CrashLoopBackOff) while the internet is down

**Symptom**: the `unbound` pods restart repeatedly or sit in `CrashLoopBackOff` while the home internet is down or degraded, and internal names (stub zone `iseja.net`, answered by `10.7.2.10`/`.12`) stop resolving through them although nothing is wrong with those servers. A restart never fixes it, because the container comes back with an empty cache.

**Cause** (found in [#2043](https://github.com/isejalabs/homelab/issues/2043)): the liveness probe runs the image's `healthcheck.sh`. With `EXTENDED_HEALTHCHECK=true` it also resolves `EXTENDED_HEALTHCHECK_DOMAIN` through unbound itself. Until [#2043](https://github.com/isejalabs/homelab/issues/2043) that domain was `k.root-servers.net`, a name unbound only knows from a real recursion to the internet, and the probe had the default 1 s timeout. Without internet the recursion fails or takes longer than 1 s, the probe fails, kubelet kills the pod, and the empty cache makes the next probe a cold recursion again.

**Check**:

```sh
kubectl -n unbound get pods
kubectl -n unbound describe pod -l app=unbound   # Events: "Liveness probe failed: ... timed out" / "Port 5335 not open"
kubectl -n unbound get deploy unbound -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}{"\n"}{.spec.template.spec.containers[0].startupProbe}{"\n"}'
kubectl -n unbound get cm | grep unbound-env     # the ConfigMap holding EXTENDED_HEALTHCHECK*, then:
kubectl -n unbound get cm <unbound-env-name> -o jsonpath='{.data}{"\n"}'
```

Then query the pod's own resolver: `dig @<unbound-lb-ip> gw.<domain>` (stub zone, must answer without internet) and `dig @<unbound-lb-ip> example.com` (needs internet or a cached answer).

**What the fix does** (base `k8s/apps/dns/unbound/base/`, inherited by every environment):

- `EXTENDED_HEALTHCHECK_DOMAIN=localhost` keeps the extended check (unbound must really answer a query) but on a name from unbound's built-in local zone, so the probe never needs the internet or the LAN stub servers.
- A `startupProbe` (up to 150 s) keeps the liveness probe off while unbound starts; the liveness probe has a 5 s timeout and 6 consecutive failures.
- There is deliberately no readiness probe on an upstream name: it would pull the pod out of the Service and take the internal zones down too.
- `prefetch: yes` and `serve-expired: yes` (bounded by `serve-expired-ttl`) let external names keep answering from stale cache during an outage.

If a pod still restarts, `kubectl -n unbound logs <pod> --previous` shows whether unbound itself crashed (then it is a different problem) or was killed by the probe.

## 5. External names return SERVFAIL through Unbound (DNSSEC)

**Symptom**: a public name answers via AdGuard/Quad9 but returns `SERVFAIL` when queried at Unbound directly, while internal names (`iseja.net`, the `10.in-addr.arpa` reverse zone) are fine.

**Cause**: Unbound validates DNSSEC (the `auto-trust-anchor-file` in [`unbound.conf`](../k8s/apps/dns/unbound/base/config/unbound.conf), see [`network.md`](architecture/network.md#dns-adguard--unbound)) and rejects answers whose signatures do not verify: a genuinely broken zone, a clock that is off (validation depends on correct time on the node), or a root key file that did not load. `iseja.net` is never validated (`domain-insecure`).

**Check**: ask with and without validation. If the `+cd` query answers but the plain one gives `SERVFAIL`, validation is what rejects it:

```sh
dig @<unbound-lb-ip> +dnssec <name>        # status: SERVFAIL = rejected, flag "ad" = validated
dig @<unbound-lb-ip> +cd <name>            # +cd = checking disabled, returns the data anyway
dig @<unbound-lb-ip> +dnssec dnssec-failed.org   # must be SERVFAIL (deliberately broken test zone)
dig @<unbound-lb-ip> +dnssec cloudflare.com      # must be NOERROR with "ad" in the flags
kubectl -n unbound logs deploy/unbound | grep -iE 'trust|anchor|dnssec'
```

If even `cloudflare.com` has no `ad` flag, the trust anchor is not loaded. Check that `unbound-checkconf -o auto-trust-anchor-file` inside the pod (`/usr/local/unbound/unbound.d/sbin/unbound-checkconf -f /usr/local/unbound/unbound.conf -o auto-trust-anchor-file`) prints the root key path and that the node clock is correct.

## Verify the fix actually took

`dig` again from the actual layer a real LAN client uses first (`@<adguard-lb-ip>`), not just the layer you fixed — a correct answer at PowerDNS doesn't guarantee a client sees it yet if something upstream (Unbound's cache, AdGuard's own cache) is still holding a stale answer. If the client-facing query still looks wrong after the underlying record is confirmed correct, that's a caching/TTL wait, not a reason to keep changing the record.
