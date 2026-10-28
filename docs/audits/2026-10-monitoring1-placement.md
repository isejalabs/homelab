# Moving monitoring1 to pve1 instead of dev-ctrl-03 — 2026-10-28

**Date:** 2026-10-28. **Status:** Assessment complete; nothing moved or resized. Supersedes option 4 of the [Proxmox capacity audit](2026-10-proxmox-capacity.md#options-considered), which rejected the move on the numbers of 2026-10-19. **Scope:** whether `monitoring1` (CT 7002061, now on pve5) is a better candidate than `dev-ctrl-03` to move to pve1 to relieve pve5. It does not re-measure CPU or load (unchanged since the capacity audit) and does not cover disk or network. **Origin:** Claude (Claude Code), read-only SSH to pve5 (Proxmox API, RRD, `pct config`, the container's cgroup); pve1's guest peaks are the 7-day values of the capacity audit, not re-read. **Tracking:** [#1783](https://github.com/isejalabs/homelab/issues/1783), related [#71](https://github.com/isejalabs/homelab/issues/71) and [#1845](https://github.com/isejalabs/homelab/issues/1845).

## Result

- **`monitoring1` does not fit on pve1 as it is:** its 7-day peak is 9.6 GiB against about 9 GiB of headroom over the peaks of pve1's guests.
- **It fits only with fewer Ultimate sites.** After `core` is retired it needs about 7 GiB (about 2 GiB headroom left on pve1, thin); after `dev_k8s` is also stopped about 4 GiB (about 5 GiB left, the same as moving `dev-ctrl-03`).
- **`dev_k8s` is meant to stay running** (owner, 2026-10-28), so `dev-ctrl-03` remains the recommended move to pve1. Revisit `monitoring1` if `dev_k8s` stops being needed.

## `monitoring1` on 2026-10-28

| Item | Value |
| --- | --- |
| Memory limit | 10 GiB, no swap (`memory: 10240`), 3 cores |
| 7-day Proxmox peak | 9.64 GiB (9.4 GiB in the capacity audit) |
| Inside the container | 8.56 GiB anon, 0.35 GiB file, 0.05 GiB shmem; cgroup total 9.0 GiB |
| Per site (RSS) | `qa_k8s` 2.92 GiB, `dev_k8s` 2.81 GiB, `core` 2.60 GiB, processes of `root` 0.15 GiB |
| CPU | 0.14 cores |
| Storage | `local-enc:subvol-7002061-disk-0`, 11 GB, a node-local ZFS pool that also exists on pve1 (210 GiB free) |
| Network | `vmbr0`, VLAN tag 102, DHCP, firewall on |
| Managed by | Not Terraform (no match under `terragrunt/`) |

The growth since the September audits comes from the number of Ultimate sites: each takes 2.3 to 2.9 GiB however small it is ([capacity audit](2026-10-proxmox-capacity.md#checkmk-sites-in-monitoring1-and-monitoring2)). `dev_k8s` was stopped on 2026-10-19 and re-enabled on 2026-10-22 ([#1845](https://github.com/isejalabs/homelab/issues/1845)).

## Headroom on pve1

pve1 has 46.8 GiB; the 7-day peaks of its guests sum to 37.5 GiB (capacity audit), which leaves about 9 GiB. That sum includes `rebuild-work-01` (4.9 GiB peak), as it must: `rebuild` is expected to be up from time to time, and pve1 needs room for it regardless of how often or when (owner, 2026-10-28). The last two rows are estimates (the current peak minus the stopped sites), not measurements.

| What moves to pve1 | pve1 headroom afterwards | Freed on pve5 |
| --- | --- | --- |
| `dev-ctrl-03` (4 GiB allocated, 4.1 GiB peak) | about 5 GiB | about 4 GiB |
| `monitoring1` as it is (9.6 GiB peak) | about -0.6 GiB, does not fit | 9.6 GiB |
| `monitoring1`, `core` retired, `dev_k8s` running (about 7 GiB) | about 2 GiB, thin | about 7 GiB |
| `monitoring1`, `core` retired, `dev_k8s` stopped (about 4 GiB) | about 5 GiB | about 4 GiB |

## Why `dev_k8s` stays

The only purpose of `dev_k8s` is to anticipate the load of new apps for prod, to size requests and limits. It stays until [#71](https://github.com/isejalabs/homelab/issues/71) settles or another way to size is found, for example `kubectl top pods`, or doing the sizing in `qa` (whose site `qa_k8s` is already on `monitoring1`). This is the owner's statement; it is the deciding input for the third row above.

## Other findings

- **The live usage understates the pressure while `rebuild` is down.** The `rebuild-*` workers are not running, so pve5 shows 37.6 of 46.8 GiB used (9 running guests, 39.0 GiB allocated) and pve1 37.7 of 46.8 GiB (15 guests, 37.5 GiB allocated). The headroom figures above count `rebuild-work-01` on pve1 and `rebuild-work-02` on pve5, which is the right basis because `rebuild` comes up from time to time: a plan that leaves pve1 with about 2 GiB is thin in exactly those periods. Without `rebuild-work-01` the third row would leave about 7 GiB on pve1, but that room is not available to a permanent guest.
- **The failure-domain objection weakens once `core` is retired.** The capacity audit rejected the move partly because a pve1 failure would take out the monitor of the gateway, directory, Home Assistant and PBS. With `core` (Smart Ping of the gateways) gone, `monitoring1` only watches `qa_k8s` and `dev_k8s`, and the sites that watch pve1's services (`prod`, `free`, `prod_k8s`) are on `monitoring2` (pve4). `monitoring1` already shares pve5 with the gateway `gw3` today.
- **The move is cheap in operations.** As an LXC on local ZFS it cannot be live-migrated, but `pct migrate 7002061 pve1 --restart` should cost a few minutes of downtime for the QA and dev Checkmk sites, against the interim-control-plane procedure in [`node-lifecycle.md`](../node-lifecycle.md#5-moving-a-node-to-another-proxmox-host) for `dev-ctrl-03`. The command was not run and the migration time was not measured.
- **CPU is not a factor:** pve1 averages 25 to 29% host CPU and `monitoring1` adds 0.14 cores, less than `dev-ctrl-03` (0.22 to 0.33).

## Recommended order

1. Retire `core` (phase 2b of the [consolidation plan](../plans/2026-10-checkmk-consolidation.md)): about 2.6 GiB less on `monitoring1`, useful whichever VM moves.
2. Measure `monitoring1` for a week, then lower its memory limit (plan phase 4), keeping the web-interface swing of about 0.8 GiB in mind.
3. Move `dev-ctrl-03` to pve1 as in the capacity audit.
4. Revisit moving `monitoring1` only if `dev_k8s` stops being needed.

## Open

- **Whether VLAN 102 and the firewall settings of `vmbr0` are the same on pve1.** Not checked.
- **`monitoring1`'s peak after `core` is retired.** The 7 GiB and 4 GiB above are subtractions, not measurements.
