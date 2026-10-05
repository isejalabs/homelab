# Cilium with BGP for LoadBalancer IP advertisement

## Status

current

## Context

Cilium came with the reference stack followed when starting this project (see [ADR 0001](0001-proxmox-and-talos.md)) — it was already in place from the first dev-environment implementation (2024-11-24), not separately evaluated against other CNIs (Calico, Flannel). What *was* a deliberate, later decision is how Cilium advertises `LoadBalancer`/Gateway IPs onto the network: the Talos nodes' own interfaces live on a dedicated VLAN (`10.7.8.0/24`), completely separate from the `10.8.0.0/16` range each environment's LB-IP pool is carved out of (see [`network.md`](../architecture/network.md#cilium-lb-ipam-and-bgp-route-advertisement)) — no node has an interface anywhere in that LB-IP range at all.

## Options considered

- **L2 announcement (gratuitous ARP) (rejected)** — Cilium's other native LB-IP mechanism, but it requires the advertised IP to sit in the *same* L2 segment as the node advertising it. It structurally cannot work across the VLAN boundary between the node subnet and the LB-IP range.
- **BGP (chosen)** — a routing-layer (L3) protocol, so any node can advertise a route for any LB IP regardless of what subnet its own interface lives in; the router (a pair of OPNsense firewalls) just adds that route to its table like any other. This also decouples the LB-IP address space from node placement — an IP can be reassigned to any node, or advertised redundantly from several, without any node needing to hold it as a local address.

## Decision

Cilium's native `bgpControlPlane`, peering every worker node (control-plane nodes excluded) to both OPNsense boxes independently via `CiliumBGPClusterConfig` — see [`network.md`](../architecture/network.md#cilium-lb-ipam-and-bgp-route-advertisement) for the live configuration. Not a separate load-balancer controller (e.g. MetalLB) — Cilium's own LB-IPAM plus its BGP control plane covers both the IP allocation and the route-advertisement halves of the problem.

## Consequences

- LB-IP advertisement survives a node being drained/replaced — the route is re-advertised from whichever node currently holds the Service/Gateway, not tied to a fixed node's local address.
- Redundancy comes from peering to *both* OPNsense boxes independently per node, rather than from the CNI layer alone — losing one OPNsense box doesn't drop advertised routes.
- Depends on Cilium's own BGP control plane rather than a separate, more narrowly-scoped tool (MetalLB) — one fewer moving part, but BGP-specific troubleshooting (peering state, route advertisement) is now part of what the CNI itself needs to get right, not isolated to a dedicated LB controller.
