# Checkmk site consolidation plan

**Date:** 2026-10-20. **Status:** Planning; nothing implemented, nothing changed on any host. **Scope:** lowering CPU and memory of the Checkmk containers `monitoring1` (pve5) and `monitoring2` (pve4) by changing check intervals in `free` and by retiring the `free` and `core` sites. It does not cover the Kubernetes monitoring content of the `*_k8s` sites or the log-collection work in [#71](https://github.com/isejalabs/homelab/issues/71). **Assessment:** [Proxmox capacity audit](../audits/2026-10-proxmox-capacity.md#checkmk-sites-in-monitoring1-and-monitoring2) and [check intervals and licence state](../reference/monitoring-sites.md#check-intervals-and-licence-state). **Tracking:** [#1783](https://github.com/isejalabs/homelab/issues/1783), umbrella [#71](https://github.com/isejalabs/homelab/issues/71).

## Goal

Free about 1.2 to 1.5 GiB on `monitoring2` (pve4) and about 2.3 GiB on `monitoring1` (pve5), and lower the CPU of the two Nagios sites on pve4, without losing early detection of host outages. The estimates and their basis are in the audit.

## Decisions taken by the owner (2026-10-20)

- A 5-minute interval is fine for the services of `free` ("service checks in prod, incl. those migrated from `free`, are okay to run at 5 minutes").
- Host pings on Nagios (Community) run at 1 minute, for physical hosts and for VMs and LXCs, as long as they stay cheap.
- Pings that must be quick (down to one second) do not belong on Nagios. They belong on a CMC site: `core`, or `prod_k8s` as the production-grade commercial site. The aim is fewer sites: `free` into `prod`, `core` into `prod_k8s`.
- For `core` merged into `prod_k8s`, only the ping host checks are needed, not the services (these are covered by `prod` and `free`). `core` was only used for Smart Ping, so it is not needed any more once Smart Ping runs somewhere else.
- `pve2` and `pve3` (test Proxmox hosts, offline for months) stay in monitoring and in the inventory in case they are powered on. If keeping them costs load, remove their services and find another solution (to be decided).
- History: keep and migrate the history of the Proxmox hosts of `free` (long-term CPU and memory figures). The history of the other hosts of `free` (ping statistics and events of local and remote network gear) may be lost.
- One-second Smart Ping is needed for `core-switch`, `google-dns`, `gw`, `gw-kdg`, `gw2`, `gw3`, `gw4` and `sw01`; 6 seconds (the default) is enough for `ap-kueche` and `ap-wozi`. `mailbox.rollernet.us` and `www.heise.de` do not need Smart Ping and move to `prod` (1-minute ping). `plug-trockner`, `plug-waschmaschine`, `ns-quad9` and `pi4.dir` stay in monitoring, in `prod` only (not in `core` or `prod_k8s`).
- The 80 deployment and namespace services in `prod_k8s` that also exist in `prod` stay, as long as the 750-service limit is not at risk. Removing the node services is the first countermeasure and should be enough.
- `pve2` and `pve3` stay as they are (see phase 0 for what they cost).
- Ping-only hosts and all other hosts keep the same names in every site (no suffix).
- Licence limit alerting: consider moving services out of a free-state site at 90% of 750 (675); a check on the service count of each Ultimate site should WARN at 90% (675) and go CRIT at 95% (713), preferably as active monitoring in `prod` and/or `prod_k8s`.
- `prod_k8s` is for dynamic monitoring of the production Kubernetes cluster only. Services that `prod` already covers may be removed there, in particular the services of the Kubernetes nodes (`prod-ctrl-0x`, `prod-work-0x`, 19 services each).

## Starting point

| Site | Container | Core | Role today | CPU / memory (measured) |
| --- | --- | --- | --- | --- |
| `prod` | monitoring2 | Nagios (Community) | Central site, remote site `free` attached | 0.44 cores / 1.2 GiB |
| `free` | monitoring2 | Nagios (Community) | Remote site (`replication: slave`), physical hosts and network | 0.31 cores / 1.5 GiB |
| `prod_k8s` | monitoring2 | CMC (Ultimate, licence state Free) | Production Kubernetes cluster | 0.10 cores / 2.8 GiB |
| `core` | monitoring1 | CMC (Ultimate, licence state Free) | Smart Ping of 22 hosts (12 at 1 second, 10 at 6 seconds), plus 636 services | 0.04 cores / 2.3 GiB |

`core` monitors 17 of its 22 hosts a second time: the 12 one-second hosts below and `pve1` to `pve5` also exist in `free` (with their own agent services, for example 74 services for `pve1` in `core` against 77 in `free`). Only `monitoring1`, `ns-quad9`, `pi4.dir`, `plug-trockner` and `plug-waschmaschine` exist only in `core`; the two plugs and `pve2`/`pve3` are DOWN (the plugs are `unavailable` in Home Assistant as well).

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
4. What `pve2` and `pve3` cost (decided: leave them as they are). The services do not matter for the load, because the Checkmk agent data of a host is fetched by a single `check_mk` run (the caching agent on the target answers repeated queries); an offline host costs a process that waits and times out. Per hour that is 120 host checks (1 per minute and host, each waiting about 3.8 seconds), 24 `Check_MK` service checks (every 5 minutes, about 6 seconds until the timeout) and about 1 discovery run (every 125 minutes, about 8 seconds): about 145 runs per hour, 0.04 per second, against about 9 spawned processes per second for `free` in total (under 0.5%). The nodes are offline, so no load reaches them. What remains is noise in the problem views: acknowledge or put the hosts in a long downtime if it bothers.

### Phase 1 — `free`: intervals (configuration only)

1. Change the service check interval for `free` to 5 minutes: extend the rule "Longer check interval" (id `ddadd8db-…`, condition `Check_MK$`) or add a catch-all rule for the `free` hosts. Affects 153 services (140 passive, 13 active) and lowers the scheduled executions of `free` from about 242 to about 120 per minute. Keep the existing 15-minute and 5-minute exceptions (RustFS and Longhorn rules).
2. The rule "Normal check interval for Network Devices" (id `b308a945-…`, 1 minute for `Check_MK$` in folder `network-2`) stays at 1 minute for the network devices if the owner wants fast service feedback there; this is the owner's call.
3. Host check interval: do not change anything for the 12 one-second hosts yet if phase 2 follows soon; otherwise set both folder rules (`1e8aad76-…` and `46616260-…`) to 1 minute as the interim state.
4. Activate changes on `free` (through `prod`, the central site).
5. **Verify:** `lq "GET status"` on `free` shows lower `service_checks_rate` (target below 2 per second, from 3.3 to 5.4) and, after step 3, `host_checks_rate` below 1 per second (from 5.8); the spawn rate drops; no new UNKNOWN or PEND services; the cumulative CPU of `free` falls over the next hours.
6. **Rollback:** revert the rule changes and activate.

### Phase 2 — Make room in `prod_k8s`, then move the pings and retire `core`

**2a. Remove the node services from `prod_k8s`.** The six Kubernetes node hosts have 19 services each in `prod_k8s` (114 of 679). `prod` already monitors the same hosts from the same piggyback source (`cmk-k8s-cluster-collector.prod.iseja.net`) and shows the same services with the same values (compared on `prod-ctrl-03`: the 17 data services such as `CPU load`, `Kubelet`, `Pod resources`, `Condition` and `Info` exist in both). Only `Check_MK Discovery` and `Check_MK HW/SW Inventory` exist only in `prod_k8s`. Overall 191 of the 679 services of `prod_k8s` also exist on the same host in `prod`: 102 of 114 on nodes, 35 of 347 on deployments, 45 of 128 on namespaces, 9 of 10 on the cluster host.

1. Remove the services of the six node hosts in `prod_k8s` (for example with the rule set "Disabled services" for the six host names, or by excluding the node objects in the dynamic host configuration); the dynamic connection must not recreate them. Which mechanism to use is to be checked in the Checkmk interface.
2. Do not touch deployments, namespaces and daemonsets in this step. Their overlap is partial (a deployment host exists in `prod` for only 5 of 38) and they are the dynamic part that `prod_k8s` is for.
3. **Verify:** the service count of `prod_k8s` falls from 679 to about 565 (headroom from 71 to about 185), the scheduled executions of `prod_k8s` fall by about 21% (114 of 535 per minute), and `prod` keeps all 21 services on each node.
4. **Rollback:** remove the rule and rediscover.
5. **Alert on the service count** (WARN 675 = 90%, CRIT 713 = 95% of 750) with standard functionality: the rule set **"Checkmk site performance and settings"** (Setup, Services, Service monitoring rules, Applications, Processes & Services; check `livestatus_status`) has the parameter "Levels services" (warning and critical at or above, in services). It applies to the existing service `OMD <site> performance` of each site in `prod`, item "Name of the monitoring site", and compares `num_services` of the site's livestatus, the same number Checkmk's licence check reads. Create one rule for the sites `prod_k8s`, `qa_k8s` (and `dev_k8s` once it runs, and `core` while it lives) with 675 and 713. The service already shows the value as the metric `monitored_services` (for example 679 for `prod_k8s`). Found in the plugin source (`livestatus_status.py` and its WATO rule), and not documented in the self-monitoring article, which only says that the other site statistics are not configurable; the earlier statement in this plan that no standard check could alert was wrong. Alternatives considered and not needed: the community extension "Service Metric Counter" (Exchange, MIT, sums a metric over livestatus-matched services via the REST API and applies upper levels), a classical active check, or a local check; see the convention "Reuse before you build" in [`AGENTS.md`](../../AGENTS.md).
   - **Verify:** set a test level below the current value (for example 600 and 700 for `prod_k8s`) on a copy of the rule, confirm that the service turns WARN, then set 675 and 713.

**2b. One-second pings on `prod_k8s`.**

1. Test with one host first: create a host in `prod_k8s` with no agent and no SNMP (ping only), host check via Smart Ping, and confirm it has **no services** (the service count stays as measured after 2a). Whether CMC allows a host without services and which Smart Ping settings apply is documented only in general terms ([CMC differences](https://docs.checkmk.com/latest/en/cmc_differences.html)): check on the test host. Smart Ping sends one packet every n seconds (default 6) and marks a host DOWN when no packet arrives within a timeout (default 15 seconds, 2.5 intervals at the default), which the rule set "Settings for host checks via Smart PING" changes per host; set the timeout together with the 1-second interval and check how quickly a DOWN is reported.
2. Add as host-only hosts, ten in total: `core-switch`, `google-dns`, `gw`, `gw-kdg`, `gw2`, `gw3`, `gw4` and `sw01` with the interval of the rule set "Normal check interval for host checks" at 1 second, and `ap-kueche` and `ap-wozi` at the 6-second default. The other four hosts of `core` and `free` are handled in `prod`, not here:
   - `monitoring1`, `ns-quad9` and `pi4.dir` already exist in `prod` (1-minute ping, 100, 1 and 46 services); `core`'s duplicate entries are dropped with `core`.
   - `plug-trockner` and `plug-waschmaschine` (DOWN, only in `core`) are new hosts in `prod` with a 1-minute ping.
   - `mailbox.rollernet.us` and `www.heise.de` (WAN targets, 1 service each, only in `free`) move to `prod` with the merge in phase 3 at a 1-minute ping (keep the WAN ping levels: 6 packets, 20 second timeout).
   - The Proxmox hosts stay in `prod` after phase 3 with a 1-minute ping and need no Smart Ping.
3. After phase 3 the hosts `gw2`, `gw3`, `gw4`, `sw01`, `core-switch`, `ap-kueche`, `ap-wozi`, `gw` and `gw-kdg` exist in `prod` (with their agent services and a 1-minute ping) and as ping-only hosts in `prod_k8s`. Use the same names only if Checkmk allows duplicates across the unconnected sites without confusing notifications; otherwise use a suffix (to be checked on the test host).
4. Run both for a few days. Compare outage detection between the old and the new ping.
5. Set the host check interval of the hosts in `free` to 1 minute as soon as 2b step 4 shows the same detection (the folder rules `1e8aad76-…` and `46616260-…`).
6. Stop `core`: `omd stop core` and `omd config core set AUTOSTART off` (the way `dev_k8s` was stopped), keep the data as a restorable archive. Then reduce the memory of CT 7002061 (monitoring1) once its new peak is known, which relieves pve5.
7. **Verify:** `prod_k8s` services unchanged, host checks per second as expected, CPU of `prod_k8s` and of the `monitoring2` container, memory of `monitoring1` after the stop, the pve5 memory headroom.
8. **Rollback:** `omd start core` and `omd config core set AUTOSTART on`; remove the new hosts from `prod_k8s`.

### Phase 3 — Merge `free` into `prod`

1. Pre-checks: which hosts and agents belong to `free` (tag `site: free`), and which agents are registered at `free`'s agent receiver. After the move the agents must register at `prod`; the Salt-managed re-registration used during the 2.5 upgrade is the model (not verified for the hosts of `free`).
2. History (decided): copy the RRD directories of the six Proxmox hosts from `free` to `prod` before the first checks of the moved hosts, `~/var/pnp4nagios/perfdata/pve{1,2,3,4,5,6}.home.iseja.net/` (together 214 MB: 51, 13, 32, 46, 45 and 27 MB), including the `.xml` files, with the owner of `prod`, while both sites are stopped for these hosts. The RRD layout of `free` and `prod` has the same resolutions (1 minute for 2 days, 5 minutes for 10 days, 30 minutes for 90 days, 6 hours for 1,460 days), only the order of the archives in the file differs. The history of the other 12 hosts is left in the stopped `free` site (the whole `perfdata` directory is 389 MB, so copying it all is also cheap if the owner prefers). Availability and event history stay in the archive.

   What exists: the RRDs of `pve2` end at 2026-01-08 and of `pve3` at 2026-06-23 (their last updates), those of `pve1`, `pve4`, `pve5` and `pve6` are current. Proxmox's own RRD is not a substitute: for the year it keeps weekly steps (1,257 points of 604,800 seconds, since 2025-06-19), the Checkmk RRDs keep 6-hour steps for four years.
3. Before the move, set the host check interval of the folder rules `1e8aad76-…` (folder `external_sites`) and `46616260-…` (folder `network-2`) to 1 minute (phase 1 or 2b step 5 does this), otherwise the moved hosts keep pinging every second on the Nagios site `prod`. `mailbox.rollernet.us` and `www.heise.de` then use the standard Nagios WAN ping of `prod`: the rule "Allow longer round trip times when pinging WAN hosts" (id `a697ce00-…`, tag `networking:wan`: 6 packets, 20 second timeout, round trip 1,500/3,000 ms) is already identical in `prod` and `free`, because `free` carries the central configuration of `prod`. No Smart Ping or CMC-specific setting resides in `free` (checked: no such rule or global setting; the only fast settings are the two Nagios folder rules above), so nothing of that kind is taken over.
4. Change the monitoring site of the hosts from `free` to `prod` (host attribute "Monitored on site"), run a service discovery on each, activate changes, then remove the `free` connection from `prod`.
5. Stop `free` (`omd stop free`, AUTOSTART off), keep it as the archive for a defined time, then delete.
6. **Verify:** hosts and services in `prod` are OK and not PEND, notifications arrive (first test: a test notification), the 5-minute and 1-minute intervals from phases 1 and 2 hold, RAM of the container falls by about 1.2 to 1.5 GiB, the CPU drop is about 0.03 cores plus the phase 1 effect.
7. **Rollback:** `omd start free`, move the hosts back.

### Phase 4 — Right-size and document

1. Lower the memory limits of CT 7002056 and CT 7002061 only with the web-interface swing in mind (the apache workers of `prod` and `prod_k8s` grew by about 0.8 GiB within minutes, see the [time series](../audits/2026-10-proxmox-capacity.md#time-series-inside-monitoring2-2026-10-20-0722-to-0952)). Measure for a week first; the 10 GiB of `monitoring2` was raised on 2026-10-19 after the [OOMs](../audits/2026-10-monitoring-container-oom.md), do not lower it blindly.
2. Update [`monitoring-sites.md`](../reference/monitoring-sites.md) (containers, sites, intervals), the [capacity audit](../audits/2026-10-proxmox-capacity.md) with a new dated audit of the result (do not edit the old one), and the agreed constraints in [#71](https://github.com/isejalabs/homelab/issues/71).

## Risks

- **`prod_k8s` has 71 services of headroom** (about 185 after step 2a). Hosts added in phase 2b must not bring services; every new Kubernetes workload adds some. If the limit is reached, Activate changes is blocked until services are removed.
- **Four sites in licence state Free.** The code counts per site; Checkmk's pages describe the free mode as one site. Retiring `core` reduces the exposure. Whether the remaining setup is within the terms was not checked.
- **A second Ultimate site is not needed after the merge,** but `qa_k8s` (and the stopped `dev_k8s`) stay on `monitoring1`.
- **Moving hosts loses history** unless the RRD files are copied by hand; the old site stays as the archive.
- **Smart Ping reported as broken** in `core`: until phase 0 clarifies it, do not rely on it as the only ping source.
- **Load shifts from pve5 to pve4:** `core`'s 0.04 cores and the new hosts' memory move onto `monitoring2`, on the node with the highest load. The estimated size is small (the Smart Ping cost is measured at 0.04 cores for 22 hosts), but it adds to pve4.

## Open questions for the owner

None open at the moment. The earlier question about the mechanism for the service-count alert is resolved by the standard rule set above.
