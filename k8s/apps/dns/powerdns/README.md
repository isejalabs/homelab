## Per-environment TSIG key setup

External-dns's dynamic updates into an environment's `<env>.iseja.net` zone are authorized by a TSIG key,
delivered via `ExternalSecret`/1Password — see
[`k8s/components/transformers/powerdns-tsig-env/README.md`](../../../components/transformers/powerdns-tsig-env/README.md)
for how the per-env `#<env>` item-key rewriting works. Before a new environment's PowerDNS can reconcile
successfully, create its 1Password item once:

1. Generate a base64 HMAC-SHA256 secret — either is fine, the value is what matters, not how it was made:

   ```sh
   openssl rand -base64 32
   ```

   or, if you want the key name baked into the generation step for your own records (`tsig-keygen` prints a
   full BIND-style `key "name." { algorithm ...; secret "..."; };` line — only the string inside
   `secret "..."` is the value you need, not the whole line):

   ```sh
   tsig-keygen -a hmac-sha256 dynupdate
   ```

2. In the shared `K8S` 1Password vault, create an item named `powerdns-tsig-dynupdate#<env>` (e.g.
   `powerdns-tsig-dynupdate#dev`) with a single field `TSIG_DYNUPDATE_SECRET` holding that base64 value.

That's the only manual step — the `ExternalSecret`/transformer/`pdnsutil` zone-bootstrap `initContainer`
handle everything else automatically once the item exists.

## Per-environment `axfr-out` TSIG key setup

A second, separate key authorizes `10.7.2.12` (the LXC secondary, outside this repo) to AXFR each
environment's `<env>.iseja.net` zone — deliberately not the same key as `dynupdate` above, since it's a
different trust relationship (an external physical box, not the in-cluster external-dns pod). Same process,
different item:

1. Generate a base64 HMAC-SHA256 secret the same way as above.
2. Create a 1Password item named `powerdns-tsig-axfr-out#<env>` with a single field `TSIG_AXFR_OUT_SECRET`
   holding that value.

This key also needs configuring on `10.7.2.12` itself (outside this repo) once it's actually set up to slave
the zone — not something this repo's manifests can do.

## Per-environment PTR/reverse-zone setup

Alongside the forward `<env>.iseja.net` zone, PowerDNS also hosts a PTR zone for that environment's own
`10.8.<env-id>.0/24` LB-IP range (see [`docs/architecture/network.md`](../../../../docs/architecture/network.md)'s
zone-inventory table), populated the same dynamic way by external-dns's `--create-ptr`. Unlike `ZONE`, this
value isn't derivable from `DOMAIN_BASE`/`DOMAIN_TLD` — it's tied to each environment's own Cilium LB-IPAM
pool (`k8s/infra/kube-system/cilium/envs/<env>/ip-pool-bgp.yaml`), an unrelated addressing scheme — so a new
environment needs its own `DNS_REVERSE_ZONE` value added to
[`k8s/components/envs/<env>/cluster-param.yaml`](../../../components/envs), e.g. `3.8.10.in-addr.arpa.` for
an env whose LB-IP pool is `10.8.3.0/24`. See
[`k8s/components/transformers/reverse-zone-env`](../../../components/transformers/reverse-zone-env) for how
that value gets wired into both PowerDNS's own zone-bootstrap `initContainer` and external-dns's
`domainFilters`/`--rfc2136-zone`.
