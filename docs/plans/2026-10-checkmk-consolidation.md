# Checkmk site consolidation plan

**Date:** 2026-10-20. **Status:** Planning; nothing implemented, nothing changed on any host. **Scope:** lowering CPU and memory of the Checkmk containers `monitoring1` (pve5) and `monitoring2` (pve4) by changing check intervals in `free` and by retiring the `free` and `core` sites. It does not cover the Kubernetes monitoring content of the `*_k8s` sites or the log-collection work in [#71](https://github.com/isejalabs/homelab/issues/71). **Assessment:** [Proxmox capacity audit](../audits/2026-10-proxmox-capacity.md#checkmk-sites-in-monitoring1-and-monitoring2) and [check intervals and licence state](../reference/monitoring-sites.md#check-intervals-and-licence-state). **Tracking:** [#1783](https://github.com/isejalabs/homelab/issues/1783), umbrella [#71](https://github.com/isejalabs/homelab/issues/71).

## Goal

Free about 1.2 to 1.5 GiB on `monitoring2` (pve4) and about 2.3 GiB on `monitoring1` (pve5), and lower the CPU of the two Nagios sites on pve4, without losing early detection of host outages. The estimates and their basis are in the audit.

## Decisions taken by the owner (2026-10-20)

- A 5-minute interval is fine for the services of `free` ("service checks in prod, incl. those migrated from `free`, are okay to run at 5 minutes").
- Host pings on Nagios (Community) run at 1 minute, for physical hosts and for VMs and LXCs, as long as they stay cheap.
- Pings that must be quick (down to one second) do not belong on Nagios. They belong on a CMC site: `core`, or `prod_k8s` as the production-grade commercial site. The aim is fewer sites: `free` into `prod`, `core` into `prod_k8s`.
- For `core` merged into `prod_k8s`, only the ping host checks are needed, not the services (these are covered by `prod` and `free`).

## Starting point

| Site | Container | Core | Role today | CPU / memory (measured) |
| --- | --- | --- | --- | --- |
| `prod` | monitoring2 | Nagios (Community) | Central site, remote site `free` attached | 0.44 cores / 1.2 GiB |
| `free` | monitoring2 | Nagios (Community) | Remote site (`replication: slave`), physical hosts and network | 0.31 cores / 1.5 GiB |
| `prod_k8s` | monitoring2 | CMC (Ultimate, licence state Free) | Production Kubernetes cluster | 0.10 cores / 2.8 GiB |
| `core` | monitoring1 | CMC (Ultimate, licence state Free) | Smart Ping of 22 hosts, plus 636 services | 0.04 cores / 2.3 GiB |

The one-second pings in `free` come from two folder rules that set the host check interval to 0.0167 minutes: folder `external_sites` (4 WAN targets, `check_icmp -n 6 -t 20`) and folder `network-2` (8 hosts: `gw`, `gw2`, `gw3`, `gw4`, `sw01`, `core-switch`, `ap-kueche`, `ap-wozi`). The 1-minute services come from the default: the only `free` rule that lengthens the interval ("Longer check interval", 5 minutes) matches `Check_MK$` only.

## Constraints

- **Licence state Free** on every Ultimate site: 750 services per site (counted from livestatus, the label `cmk/licensing:excluded` does not help), above that Activate changes is blocked. `prod_k8s` has 679, headroom 71. Hosts added to `prod_k8s` must not add services.
- **Historic data is not moved with a host.** Checkmk's documentation ([distributed monitoring](https://docs.checkmk.com/latest/en/distributed_monitoring.html)) says that when a host moves to another site its current and historic status data are not carried over, metrics are lost unless the RRD files are moved by hand (`~/var/pnp4nagios/perfdata/` on Community sites), and availability and event history are not easy to migrate. [#71](https://github.com/isejalabs/homelab/issues/71) agreed to keep about 700 days of tiered RRD history, and accepts a restorable stopped site as an archive.
- **Checkmk configuration is manual** (no Flux or Salt for it) and has to be documented, per the agreed constraints in [#71](https://github.com/isejalabs/homelab/issues/71).
- **The earlier decision "exclude the `core` Smart Ping site" in [#71](https://github.com/isejalabs/homelab/issues/71) is replaced by this plan:** `core` is retired, its Smart Ping moves.
- **Nothing in this plan is applied from this repository.** All steps are in the Checkmk web interface or on the containers; the repository changes are documentation only.

## Phases

Each phase is independent and reversible, in this order because the cheapest, safest savings come first.

### Phase 0 — Before changing anything

1. Take a Proxmox snapshot or `vzdump` of CT 7002056 (monitoring2) and CT 7002061 (monitoring1), see [`proxmox-vm-snapshots.md`](../proxmox-vm-snapshots.md).
2. Record the baseline: cumulative CPU per site (the method of the audit), `host_checks_rate` and `service_checks_rate` from `lq "GET status"`, and the process spawn rate. The audit has the values of 2026-10-20.
3. Find out why Smart Ping in `core` is reported as not working ([`monitoring-sites.md`](../reference/monitoring-sites.md#sites)), because phase 2 relies on it. The measurement shows its host checks run (13.6 per second).
4. Decide for `pve2` and `pve3` (DOWN in `free`, 1-minute checks with a 3.8 second timeout): remove from monitoring or keep.

### Phase 1 — `free`: intervals (configuration only)

1. Change the service check interval for `free` to 5 minutes: extend the rule "Longer check interval" (id `ddadd8db-…`, condition `Check_MK$`) or add a catch-all rule for the `free` hosts. Affects 153 services (140 passive, 13 active) and lowers the scheduled executions of `free` from about 242 to about 120 per minute. Keep the existing 15-minute and 5-minute exceptions (RustFS and Longhorn rules).
2. The rule "Normal check interval for Network Devices" (id `b308a945-…`, 1 minute for `Check_MK$` in folder `network-2`) stays at 1 minute for the network devices if the owner wants fast service feedback there; this is the owner's call.
3. Host check interval: do not change anything for the 12 one-second hosts yet if phase 2 follows soon; otherwise set both folder rules (`1e8aad76-…` and `46616260-…`) to 1 minute as the interim state.
4. Activate changes on `free` (through `prod`, the central site).
5. **Verify:** `lq "GET status"` on `free` shows lower `service_checks_rate` (target below 2 per second, from 3.3 to 5.4) and, after step 3, `host_checks_rate` below 1 per second (from 5.8); the spawn rate drops; no new UNKNOWN or PEND services; the cumulative CPU of `free` falls over the next hours.
6. **Rollback:** revert the rule changes and activate.

### Phase 2 — One-second pings on `prod_k8s`, retire `core`

1. Test with one host first: create a host in `prod_k8s` with no agent and no SNMP (ping only), host check via Smart Ping, and confirm it has **no services** (the service count of `prod_k8s` stays at 679). Whether CMC allows a host without services and which Smart Ping settings apply is documented only in general terms ([CMC differences](https://docs.checkmk.com/latest/en/cmc_differences.html)): check on the test host.
2. Add the 12 hosts of `free` (`external_sites` and `network-2`) and the hosts of `core` as host-only hosts in `prod_k8s`, with the "Normal check interval for host checks" rule set to the wanted value (default 6 seconds, 1 second where the owner wants it) and the "Settings for host checks via Smart PING" rule set for the timeout. WAN targets may need a different timeout.
3. Keep the same host names as in `prod` and `free` only if Checkmk allows duplicates across unconnected sites without confusing notifications; otherwise use a suffix.
4. Run both for a few days. Compare outage detection between the old and the new ping.
5. Stop `core`: `omd stop core` and `omd config core set AUTOSTART off` (the way `dev_k8s` was stopped), keep the data as a restorable archive. Then reduce the memory of CT 7002061 (monitoring1) once its new peak is known, which relieves pve5.
6. **Verify:** `prod_k8s` services unchanged (679), host checks per second as expected, CPU of `prod_k8s` and of the `monitoring2` container, memory of `monitoring1` after the stop, the pve5 memory headroom.
7. **Rollback:** `omd start core` and `omd config core set AUTOSTART on`; remove the new hosts from `prod_k8s`.

### Phase 3 — Merge `free` into `prod`

1. Pre-checks: which hosts and agents belong to `free` (tag `site: free`), and which agents are registered at `free`'s agent receiver. After the move the agents must register at `prod`; the Salt-managed re-registration used during the 2.5 upgrade is the model (not verified for the hosts of `free`).
2. Decide what happens to history: new start in `prod` with the stopped `free` site as the archive, or a manual copy of the RRD files of each host from `free` to `prod` (`~/var/pnp4nagios/perfdata/<host>/`) after the move and before the first checks. Availability and event history stay in the archive.
3. Change the monitoring site of the hosts from `free` to `prod` (host attribute "Monitored on site"), run a service discovery on each, activate changes, then remove the `free` connection from `prod`.
4. Stop `free` (`omd stop free`, AUTOSTART off), keep it as the archive for a defined time, then delete.
5. **Verify:** hosts and services in `prod` are OK and not PEND, notifications arrive (first test: a test notification), the 5-minute and 1-minute intervals from phases 1 and 2 hold, RAM of the container falls by about 1.2 to 1.5 GiB, the CPU drop is about 0.03 cores plus the phase 1 effect.
6. **Rollback:** `omd start free`, move the hosts back.

### Phase 4 — Right-size and document

1. Lower the memory limits of CT 7002056 and CT 7002061 only after a week of measurements; the 10 GiB of `monitoring2` was raised on 2026-10-19 after the [OOMs](../audits/2026-10-monitoring-container-oom.md), do not lower it blindly.
2. Update [`monitoring-sites.md`](../reference/monitoring-sites.md) (containers, sites, intervals), the [capacity audit](../audits/2026-10-proxmox-capacity.md) with a new dated audit of the result (do not edit the old one), and the agreed constraints in [#71](https://github.com/isejalabs/homelab/issues/71).

## Risks

- **`prod_k8s` has 71 services of headroom.** Hosts added in phase 2 must not bring services; every new Kubernetes workload adds some. If the limit is reached, Activate changes is blocked until services are removed.
- **Four sites in licence state Free.** The code counts per site; Checkmk's pages describe the free mode as one site. Retiring `core` reduces the exposure. Whether the remaining setup is within the terms was not checked.
- **A second Ultimate site is not needed after the merge,** but `qa_k8s` (and the stopped `dev_k8s`) stay on `monitoring1`.
- **Moving hosts loses history** unless the RRD files are copied by hand; the old site stays as the archive.
- **Smart Ping reported as broken** in `core`: until phase 0 clarifies it, do not rely on it as the only ping source.
- **Load shifts from pve5 to pve4:** `core`'s 0.04 cores and the new hosts' memory move onto `monitoring2`, on the node with the highest load. The estimated size is small (the Smart Ping cost is measured at 0.04 cores for 22 hosts), but it adds to pve4.

## Open questions for the owner

- Which of the 12 one-second hosts really need 1 second, and which are fine at 6 seconds (the CMC default)?
- Keep `pve2` and `pve3` in `free`?
- History: archive-only, or copy the RRD files of the hosts of `free`?
- Is `core` needed for anything besides Smart Ping?
