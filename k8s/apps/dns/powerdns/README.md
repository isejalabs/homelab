## Per-environment TSIG key setup

External-dns's dynamic updates into an environment's `<env>.iseja.net` zone are authorized by a TSIG key, delivered via `ExternalSecret`/1Password — see [`k8s/components/transformers/powerdns-tsig-env/README.md`](../../../components/transformers/powerdns-tsig-env/README.md) for how the per-env `#<env>` item-key rewriting works. Before a new environment's PowerDNS can reconcile successfully, create its 1Password item once:

1. Generate a base64 HMAC-SHA256 secret — either is fine, the value is what matters, not how it was made:

   ```sh
   openssl rand -base64 32
   ```

   or, if you want the key name baked into the generation step for your own records (`tsig-keygen` prints a full BIND-style `key "name." { algorithm ...; secret "..."; };` line — only the string inside `secret "..."` is the value you need, not the whole line):

   ```sh
   tsig-keygen -a hmac-sha256 dynupdate
   ```

2. In the shared `K8S` 1Password vault, create an item named `powerdns-tsig-dynupdate#<env>` (e.g. `powerdns-tsig-dynupdate#dev`) with a single field `TSIG_DYNUPDATE_SECRET` holding that base64 value.

That's the only manual step — the `ExternalSecret`/transformer/`pdnsutil` zone-bootstrap `initContainer` handle everything else automatically once the item exists.

## Per-environment `axfr-out` TSIG key setup

A second, separate key authorizes `10.7.2.12` (the LXC secondary, outside this repo) to AXFR each environment's `<env>.iseja.net` zone — deliberately not the same key as `dynupdate` above, since it's a different trust relationship (an external physical box, not the in-cluster external-dns pod). Same process, different item:

1. Generate a base64 HMAC-SHA256 secret the same way as above.
2. Create a 1Password item named `powerdns-tsig-axfr-out#<env>` with a single field `TSIG_AXFR_OUT_SECRET` holding that value.

This key also needs configuring on `10.7.2.12` itself (outside this repo) once it's actually set up to slave the zone — see the next section for exactly how.

## Configuring `ns2` (`10.7.2.12`, BIND9) as a TSIG-authenticated slave

`10.7.2.12` (`ns2.home.iseja.net`) is a Debian LXC running BIND9 (`named`), outside this repo — none of this is `kubectl`/Flux-managed, it's a manual config change on that box. It already slaves the `iseja.net` root zone from `10.7.2.10` today; this section is specifically about adding each environment's new `<env>.iseja.net` and PTR zone as *additional* slave zones, sourced from that environment's in-cluster PowerDNS instead.

Each environment has its own independent `axfr-out` TSIG secret (`powerdns-tsig-axfr-out#<env>` in 1Password — see above) and its own PowerDNS LB IP (`10.8.<env-id>.10`), so each needs its own key block and its own pair of zone stanzas; don't reuse one key name across environments, BIND9's key namespace is global to the whole server. Worked example for `dev` (`env-id` `3`, LB IP `10.8.3.10`):

1. Fetch that environment's `axfr-out` secret from 1Password (the same value ESO delivers into the cluster's `powerdns-tsig-axfr-out` Secret — 1Password is the source of truth either way):

   ```sh
   op item get powerdns-tsig-axfr-out#dev --fields TSIG_AXFR_OUT_SECRET
   ```

2. In `/etc/bind/named.conf.local` (Debian's standard include file for local zone/key config, separate from the package-managed `named.conf.options`), add a key block and a `server` statement so `named` signs both its outgoing AXFR requests and its acceptance of `NOTIFY` messages from that IP:

   ```
   key "axfr-out-dev" {
       algorithm hmac-sha256;
       secret "<paste the TSIG_AXFR_OUT_SECRET value here>";
   };

   server 10.8.3.10 {
       keys { axfr-out-dev; };
   };
   ```

3. Add the two slave zone stanzas (forward + PTR), each pointing at that same master IP/key and a local file path for the persisted transfer (BIND9 needs to persist a slave zone to disk the same way PowerDNS does — this is what lets `ns2` still answer from its last-known-good copy if the k8s master is briefly unreachable):

   ```
   zone "dev.iseja.net" {
       type slave;
       file "/var/cache/bind/db.dev.iseja.net";
       masters { 10.8.3.10 key axfr-out-dev; };
       allow-notify { 10.8.3.10 key axfr-out-dev; };
   };

   zone "3.8.10.in-addr.arpa" {
       type slave;
       file "/var/cache/bind/db.3.8.10.in-addr.arpa";
       masters { 10.8.3.10 key axfr-out-dev; };
       allow-notify { 10.8.3.10 key axfr-out-dev; };
   };
   ```

4. Validate and reload rather than a full restart (avoids dropping the zones BIND9 already slaves, e.g. the `iseja.net` root zone itself):

   ```sh
   named-checkconf
   rndc reload
   ```

5. Confirm the transfer actually happened — check the log for a successful "Transfer status: success" line, confirm the zone file materialized on disk, then query `ns2` directly (not through the resolver chain) to prove it's answering authoritatively rather than just having loaded config:

   ```sh
   journalctl -u bind9 --since "5 min ago" | grep -i "dev.iseja.net\|transfer"
   ls -la /var/cache/bind/db.dev.iseja.net
   dig @10.7.2.12 dev.iseja.net NS
   ```

Repeat steps 1-5 per environment as each one is actually ready to be slaved — no need to do all 8 in one sitting. `10.7.2.10`'s own reconfiguration (to stop sending it anything once its master reference moves) and the `iseja.net` root-zone NS/glue-record updates are separate, tracked in PR #1392's "Before merging" checklist.

## Per-environment PTR/reverse-zone setup

Alongside the forward `<env>.iseja.net` zone, PowerDNS also hosts a PTR zone for that environment's own `10.8.<env-id>.0/24` LB-IP range (see [`docs/architecture/network.md`](../../../../docs/architecture/network.md)'s zone-inventory table), populated the same dynamic way by external-dns's `--create-ptr`. Unlike `ZONE`, this value isn't derivable from `DOMAIN_BASE`/`DOMAIN_TLD` — it's tied to each environment's own Cilium LB-IPAM pool (`k8s/infra/kube-system/cilium/envs/<env>/ip-pool-bgp.yaml`), an unrelated addressing scheme — so a new environment needs its own `DNS_REVERSE_ZONE` value added to [`k8s/components/envs/<env>/cluster-param.yaml`](../../../components/envs), e.g. `3.8.10.in-addr.arpa` (no trailing dot, same convention as `DOMAIN_BASE`/`DOMAIN_TLD` -- external-dns matches its own generated record names against this value literally and doesn't normalize a trailing dot the way PowerDNS's `pdnsutil` does) for an env whose LB-IP pool is `10.8.3.0/24`. See [`k8s/components/transformers/reverse-zone-env`](../../../components/transformers/reverse-zone-env) for how that value gets wired into both PowerDNS's own zone-bootstrap `initContainer` and external-dns's `domainFilters`/`--rfc2136-zone`.

## SOA MNAME and `ns1`'s own record

Every zone's NS record and SOA MNAME point at `ns1.<env>.iseja.net` (set at `zone create` time in `bootstrap-zone.sh`), so PowerDNS's own `Service` carries an `external-dns.kubernetes.io/hostname: ns1.<env>.iseja.net` annotation -- without it, that name has no A/PTR record of its own (confirmed live: NXDOMAIN), an incomplete NS configuration even though the NS/SOA records referencing it are otherwise correct. Note this is *not* the usual per-app `dev-<app>`-style hostname: it's wired through only `replace-domain`'s TLD/BASE split, never `prefix-domain`, since it has to match `bootstrap-zone.sh`'s own `ns1.$$zone` construction exactly (an env-name prefix here would produce `dev-ns1.dev.iseja.net`, which wouldn't match).

`bootstrap-zone.sh` also explicitly sets each zone's SOA via `pdnsutil rrset replace` right after `zone create` -- PowerDNS's own `default-soa-content` default seeds a deliberately-fake MNAME placeholder (`a.misconfigured.dns.server.invalid`) meant to be overridden per zone, which nothing previously did. The replacement always uses the *forward* zone's own `ns1.$$zone` as MNAME, for both the forward and reverse zone (the reverse zone's own name has no NS/A record of its own, so it can't be its own MNAME target). Serial `0` preserves PowerDNS's documented "auto-compute serial from the zone's highest record `change_date`" convention -- safe to re-run unconditionally, since that recompute only ever moves forward in time.

## Cheat sheet

Common operational commands, tested against a live environment's PowerDNS LB IP (e.g. `10.8.3.10` for `dev`) and a TSIG key already delivered by ESO -- see [`k8s/components/transformers/powerdns-tsig-env`](../../../components/transformers/powerdns-tsig-env) for how the `#<env>` 1Password item lands in one of the two Secrets below.

### Retrieve a zone's full record set via AXFR (TSIG-authenticated)

Pull the TSIG secret straight from the Secret ESO already wrote, then `dig +axfr` against PowerDNS's own LB IP -- not `localhost`/a port-forward, since the point is to exercise the exact same TSIG-gated path `10.7.2.12` (or external-dns's own `--rfc2136-axfr`) will use:

```sh
SECRET=$(kubectl get secret -n powerdns powerdns-tsig-dynupdate -o jsonpath='{.data.TSIG_DYNUPDATE_SECRET}' | base64 -d)
dig @10.8.3.10 dev.iseja.net AXFR -y hmac-sha256:dynupdate:"$SECRET"
```

Swap the zone name for the PTR zone (`3.8.10.in-addr.arpa`) and the Secret/key name for `axfr-out` (`powerdns-tsig-axfr-out` / `TSIG_AXFR_OUT_SECRET`) to exercise the *other* TSIG grant the same way -- useful for confirming `10.7.2.12`'s eventual slave config will actually work before wiring it up on the LXC itself.

An unauthenticated AXFR (same command, no `-y`) should be refused (`; Transfer failed.` / `REFUSED`) -- confirmed live as the expected behavior, not a bug: only key names listed in a zone's `TSIG-ALLOW-AXFR` metadata may transfer it.

### Inspect a zone directly on the pod

```sh
kubectl exec -n powerdns deploy/powerdns -- pdnsutil zone list dev.iseja.net
kubectl exec -n powerdns deploy/powerdns -- pdnsutil zone list 3.8.10.in-addr.arpa
```

Faster than a `dig` round-trip for confirming what's actually in the backend, especially when diagnosing a `REFUSED`/`SERVFAIL` from `dig` itself (see quirks below) -- rules out "is the record actually there" before suspecting the network/TSIG path.

### Quirks encountered live (not obvious from the docs)

- **A CNAME can never coexist with any other record type at the same owner name.** Cutting a hostname over from a direct A record to a CNAME (see the Gateway-CNAME section above) produces a transient `REFUSED` on the very first reconcile if the old A record hasn't been deleted in the same pass yet -- self-resolves on the next reconcile once it has. Not a bug, just DNS's own rule; expect a brief blip on any A-to-CNAME cutover.
- **`TSIG-ALLOW-AXFR` is a full-replace metadata key, not additive.** A second `pdnsutil metadata set ... TSIG-ALLOW-AXFR <key>` call *replaces* the previous grant rather than adding to it -- granting both `dynupdate` and `axfr-out` needs one call listing both key names together, never two separate calls.
- **external-dns's `--rfc2136-zone` must be one combined `flag=value` string, not two array entries.** The chart's values schema requires `extraArgs` to be a set of *unique* strings; two bare `--rfc2136-zone` entries (flag and value split across array elements) collide regardless of what value follows, since uniqueness checking only sees the repeated flag token itself.
- **external-dns's `--create-ptr` refuses to start unless `PTR` is explicitly added to `--managed-record-types`.** The flag's own default set (`A`, `AAAA`, `CNAME`) doesn't include it -- fails config validation at startup otherwise (`--create-ptr requires PTR in --managed-record-types`).
- **external-dns's zone-name matching is literal, not normalized.** Unlike `pdnsutil` (tolerant of a trailing dot either way), external-dns compares its own generated record names against the exact string configured in `--rfc2136-zone`/`domainFilters` -- a trailing dot present on one side and not the other silently drops every record for that zone as "out of zone", which PowerDNS then refuses at the RFC2136 layer with little indication why.
- **PTR/CNAME record churn on every reconcile is a known upstream external-dns bug, not a local misconfiguration.** See PR #1392's "Known upstream external-dns bug" section and issue #1393 -- harmless, just wasteful; don't spend time chasing it as a config problem here.
