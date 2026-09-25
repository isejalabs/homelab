# TSIG over IP-ACL for AXFR and dynamic-update authorization

## Status

current

## Context

The DNS servers this project introduces need to authorize three kinds of write/transfer traffic: external-dns's
dynamic updates into the `<env>.iseja.net` zones, AXFR out to the surviving LXC (`10.7.2.12`, keeping its
existing slave role, just re-pointed at the new master), and AXFR in from UCS for the couple of zones it
masters. Today, every existing nameserver in this network (the LXCs, UCS) authorizes exactly this kind of
traffic by checking the request's source IP against a fixed allow-list — simple, and it works when every
nameserver has one stable, known IP.

A Kubernetes pod doesn't have that property by default: with multiple replicas (or just pod rescheduling),
outbound traffic can leave from whichever node the pod currently runs on, so a source-IP allow-list would
need every replica's egress pinned to one predictable IP to keep working.

## Options considered

- **IP-ACL via Cilium Egress Gateway** — would match the existing pattern used everywhere else on this
  network. Checked what's actually available: this repo's only Egress Gateway usage is a retired PoC in
  `_attic/` (`k8s/apps/ras/openssh` and `k8s/apps/diag/openssh`, both retired) pinning a single pod to one
  hardcoded node via `nodeSelector.matchLabels.kubernetes.io/hostname`, with the PoC's own code comment
  reading `# ToDo: use node where pod is running` — i.e. it never actually solved multi-node
  failover, only demonstrated the single-node happy path. There's also an open-but-empty tracked issue
  (`#126`, parent `#234`) for applying egress gateway to unifi, with no design notes. Building a real,
  failover-capable egress-IP story from scratch was judged out of proportion to what this DNS project
  actually needs.
- **TSIG, with IP-ACL as a second layer** — considered as defense-in-depth. Rejected as unnecessary
  complexity: TSIG alone is a complete, standard answer.
- **TSIG only** — cryptographic, per-message authorization by key name rather than source address. PowerDNS
  supports it natively for both TSIG-signed AXFR (either direction) and TSIG-gated RFC2136 dynamic updates
  (`dnsupdate-require-tsig`, per-zone `TSIG-ALLOW-DNSUPDATE`/`ALLOW-DNSUPDATE-FROM` metadata).

## Decision

TSIG only, for both AXFR and dynamic-update authorization, everywhere this project touches. Global
`allow-dnsupdate-from` stays empty; only a zone's `TSIG-ALLOW-DNSUPDATE` metadata authorizes updates to it.

## Consequences

- Authorization is completely independent of which node a pod replica happens to be running on — no egress
  IP pinning, no dependency on Cilium Egress Gateway ever getting a real multi-node failover story.
- Every party needs a shared TSIG key (external-dns, PowerDNS, and — at cutover — `10.7.2.12` and UCS) —
  key distribution becomes a real operational concern, handled via `ExternalSecret`/1Password (see
  `k8s/apps/dns/powerdns/envs/*/externalsecret.yaml`), not via `op inject` (reserved for bootstrapping
  1Password Connect itself).
- If a future requirement genuinely needs network-level restriction in addition to TSIG (e.g. a compliance
  concern, not a technical one), that's an additive layer on top of this decision, not a replacement for it.
