# Cilium as the CNI, with BGP for LoadBalancer IP advertisement

## Status

current

## Context

Cilium was chosen deliberately, not just inherited passively — it was picked specifically for its BGP support and `NetworkPolicy` capabilities, which Flannel (a common, simpler default) didn't cover. The selection process was a search for existing Kubernetes homelab projects/repos that already solved this need; [@vehagn](https://github.com/vehagn/homelab)'s implementation (see [ADR 0001](0001-proxmox-and-talos.md)) turned up as one that already used Cilium, and was adopted as the concrete reference from there — in place from the first dev-environment implementation (2024-11-24). That lineage is also why Cilium is bootstrapped via Terraform in the first place (see [ADR 0006](0006-helm-usage.md) for the mechanism) — it came that way from the adopted reference implementation, not from a separate decision to use Terraform for it specifically; deferring to a sole Helmfile-based install later (dropping the Terraform-side bootstrap) is a real possibility, not yet decided (see Open decisions).

A separate, later decision was how Cilium advertises `LoadBalancer`/Gateway IPs onto the network: the Talos nodes' own interfaces live on a dedicated VLAN (`10.7.8.0/24`), completely separate from the `10.8.0.0/16` range each environment's LB-IP pool is carved out of (see [`network.md`](../architecture/network.md#cilium-lb-ipam-and-bgp-route-advertisement)) — no node has an interface anywhere in that LB-IP range at all.

## Options considered

- **Flannel (rejected)** — a common, simpler default, but doesn't cover BGP or `NetworkPolicy`, both real requirements.
- **Cilium (chosen)** — covers both; found via searching existing Kubernetes homelab repos and adopting `@vehagn`'s reference implementation, which already used it.
- **L2 announcement (gratuitous ARP) (rejected)** — Cilium's other native LB-IP mechanism, but it requires the advertised IP to sit in the *same* L2 segment as the node advertising it. It structurally cannot work across the VLAN boundary between the node subnet and the LB-IP range.
- **BGP (chosen)** — a routing-layer (L3) protocol, so any node can advertise a route for any LB IP regardless of what subnet its own interface lives in; the router (a pair of OPNsense firewalls) just adds that route to its table like any other. This also decouples the LB-IP address space from node placement — an IP can be reassigned to any node, or advertised redundantly from several, without any node needing to hold it as a local address.

## Decision

Cilium is the CNI, chosen for BGP and `NetworkPolicy` support. For LoadBalancer IP advertisement specifically: Cilium's native `bgpControlPlane`, peering every worker node (control-plane nodes excluded) to both OPNsense boxes independently via `CiliumBGPClusterConfig` — see [`network.md`](../architecture/network.md#cilium-lb-ipam-and-bgp-route-advertisement) for the live configuration. Not a separate load-balancer controller (e.g. MetalLB) — Cilium's own LB-IPAM plus its BGP control plane covers both the IP allocation and the route-advertisement halves of the problem.

## Consequences

- LB-IP advertisement survives a node being drained/replaced — the route is re-advertised from whichever node currently holds the Service/Gateway, not tied to a fixed node's local address.
- Redundancy comes from peering to *both* OPNsense boxes independently per node, rather than from the CNI layer alone — losing one OPNsense box doesn't drop advertised routes.
- Depends on Cilium's own BGP control plane rather than a separate, more narrowly-scoped tool (MetalLB) — one fewer moving part, but BGP-specific troubleshooting (peering state, route advertisement) is now part of what the CNI itself needs to get right, not isolated to a dedicated LB controller.
- Cilium's Terraform-side bootstrap (see [ADR 0006](0006-helm-usage.md)) is inherited baggage from the adopted reference implementation, not something re-justified independently — it's a real candidate to simplify away later.

## Open decisions

- Whether to defer Cilium's install to a sole Helmfile-based approach, dropping the Terraform-side double-bootstrap described in [ADR 0006](0006-helm-usage.md) — not yet decided.
