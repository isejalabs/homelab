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
