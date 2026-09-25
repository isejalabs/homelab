# PowerDNS as the in-cluster authoritative DNS server

## Status

current

## Context

This repo is moving authority for parts of the `iseja.net` DNS namespace into Kubernetes: a per-environment
dynamic zone (`<env>.iseja.net`), auto-populated from k8s objects via external-dns, and — later, prod only —
the `iseja.net` root zone itself, IaC-managed and encrypted in git, superseding one of the two Debian LXCs
that master it today (see [`network.md`](../architecture/network.md)).

Whatever server does this needs to, in one tool if possible:

- Serve a zone whose records are written at runtime by an external-dns-style dynamic-update client.
- Serve a zone whose records are static and git/IaC-managed.
- Act as a secondary (AXFR) for a couple of zones a different system (UCS) masters.
- Act as a primary (AXFR) toward a secondary outside the cluster (the surviving LXC).
- Not require a hard new infrastructure dependency (e.g. its own etcd cluster) with no precedent in this
  repo, given the whole project is already introducing enough new surface area.

## Options considered

- **BIND9** — mature, TSIG/AXFR-native, and notably the same software family the LXCs and UCS already run
  (`network.md` documents them as BIND-based). A genuinely close second. It loses mainly on having a less
  clean story for combining a database-backed dynamic zone with file-backed static zones and secondary
  zones in one running instance the way PowerDNS's multiple simultaneous backends do — not a functional
  gap, an operational-tidiness one.
- **Technitium DNS Server** — modern, has its own web UI/REST API, growing homelab popularity. Ruled out:
  far less production track record for something this load-bearing (the root zone for the whole network),
  and no dedicated external-dns provider (would mean going through its HTTP API by hand or a generic
  webhook provider).
- **Knot DNS** — same technical class as PowerDNS (TSIG, AXFR, dynamic updates all present). Lost mainly on
  ecosystem/tooling fit for this specific combination of roles, not capability — a reasonable alternative if
  PowerDNS turns out to have problems in practice.
- **NSD** — ruled out early and structurally, not on a close call: authoritative-only, no dynamic-update
  support at all. Can't serve the `<env>.iseja.net` role regardless of anything else about it.
- **CoreDNS + etcd** — CoreDNS's `etcd` plugin plus external-dns's `coredns` provider is a well-trodden path
  elsewhere, but would mean standing up an application-level etcd cluster with zero precedent in this repo,
  purely to get a store external-dns can write into. Once TSIG/RFC2136 (see
  [ADR 0002](0002-tsig-over-ip-acl-for-axfr.md)) solved the auth question for a SQL-backed PowerDNS instead,
  this stopped having a real advantage.

## Decision

[PowerDNS Authoritative Server](https://doc.powerdns.com/authoritative/), deployed via
[`bjw-s-labs/helm-charts` app-template](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/other/app-template)
(`oci://ghcr.io/bjw-s-labs/helm/app-template`) — the standard wrapper chart in the home-operations ecosystem
this repo's own `port-app` skill is modeled on, and already implicitly referenced here via the
`k8s-schemas.bjw-s.dev` schema catalog used for `cert-manager`'s `HelmRelease`. First real consumer of that
chart in this repo ([#1378](https://github.com/isejalabs/homelab/issues/1378) uses it as the first
candidate rather than converting an existing app first, since it has zero current consumers and therefore
zero blast radius if the chart usage needs iterating on).

`gsqlite3` backend for the dynamic zone (one `PersistentVolumeClaim` per environment via the existing
`apps/storage/pvc` component), `bind`-backend zone files (Flux/`ConfigMap`-sourced, no PVC) for the
git-managed static root zone once that phase lands.

## Consequences

- One tool covers all three roles (dynamic primary, static primary, AXFR secondary/primary), rather than
  running two different DNS servers side by side.
- PowerDNS's `gsqlite3` backend is single-writer in practice (SQLite, WAL mode) — fine at this write volume,
  but means the dynamic zone stays single-replica for now rather than trivially horizontally scaled; see the
  replica-count note in `k8s/apps/dns/powerdns/base/helmrelease.yaml`'s history for the deferred
  multi-replica/RWX spike.
- Introduces a second config idiom to the `dns` app group: `adguard`/`unbound` are plain manifests,
  `powerdns` is a Helm chart. Converting the former to app-template later (if wanted) is an independent,
  lower-stakes follow-up, not a prerequisite of this decision.
