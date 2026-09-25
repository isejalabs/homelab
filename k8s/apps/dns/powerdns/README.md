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
