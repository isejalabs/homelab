# Checkmk `prod_k8s`: result of phase 2b (ping-only hosts) — 2026-10-28

**Date:** 2026-10-28. **Status:** Hosts created and verified, time to DOWN measured once; the parallel run of a few days and the effect of stopping `core` are not yet measured. **Scope:** steps 1 to 3 of phase 2b in the [consolidation plan](../plans/2026-10-checkmk-consolidation.md#phase-2--make-room-in-prod_k8s-then-move-the-pings-and-retire-core): ten ping-only hosts in `prod_k8s` next to `core`. Not covered: stopping `core`, `free`, `prod`. **Tracking:** [#1783](https://github.com/isejalabs/homelab/issues/1783). **Origin:** Claude Code session with the owner's go for each live step, read-only `lq` over SSH plus the Checkmk REST API.

Current-state documentation of the result: [`monitoring-sites.md`](../reference/monitoring-sites.md#ping-only-hosts-in-prod_k8s).

## What was changed

All in `prod_k8s`, between 22:00 and 22:30 CET:

1. Automation user `terraform` (role Administrator), created in the web interface by the owner (`prod_k8s` had only `cmkadmin` and `agent_registration`).
2. Folder `/ping-only` (no agent, no SNMP, IPv4 only), test host `gw4.home.iseja.net`, a rule in "Normal check interval for host checks" (id `34109bf2-0ce1-4d5e-b4e4-2e4f5ce853a3`, 1 second for eight hosts by name). One activation at 22:08, which needed foreign changes allowed because the only other pending change was `cmkadmin` creating the user.
3. After the finding below and the owner's acceptance: the other nine hosts and a rule in "Normal check interval for service checks" (folder `/ping-only`, `PING$`, 5 minutes). Activation at 22:27, pending list afterwards empty.

## Findings

- **A ping-only host has one service.** The test host was UP via Smart Ping at once, but `prod_k8s` went from 589 to 590 services. In Checkmk 2.5.0p15 the CMC configuration generation adds a `PING` service to a host that has no services (`cmk/base/nonfree/cmc/_services.py`: `if not cmc_services:` followed by `_add_ping_service`, comment "Nagios requires at least one service"); "Disabled services" cannot remove it. Ten hosts: 599 of 750, headroom 151, the 675 WARN level is not at risk. The services run at 5 minutes.
- **Smart Ping settings.** Default interval 6 seconds (0.1 minutes), set per host with "Normal check interval for host checks". The only parameter of "Settings for host checks via Smart Ping" (`cmc_smartping_settings`) is the timeout, by default 2.5 times the interval: 2.5 seconds for the 1-second hosts.
- **`core`'s Smart Ping works:** all ten hosts UP with "Packet received via smart PING", `icmpsender` and `icmpreceiver` running for 4 days 19 hours, no errors in `cmc.log`. `gw` is a cluster (`gw2`, `gw3`) there and uses plain `check_icmp`. `core` also pings `ap-kueche` and `ap-wozi` at 1 second, not 6.
- **Duplicate names across sites** do not confuse the cores. Notifications are per site: `core`, `prod`, `free` have no notification rules, `prod_k8s` has one with no mail address (see [`monitoring-notifications.md`](../reference/monitoring-notifications.md)).

## Measured

| | Before | After |
| --- | --- | --- |
| `prod_k8s` hosts, services | 73, 589 | 83, 599 |
| `prod_k8s` host checks per second | 1.7 | 9.4 (8 x 1 + 2 x 0.17 + 1.7 = 10 scheduled; measured 9.4 to 11.8) |
| `prod_k8s` CPU over 120 s (cumulative CPU seconds of all site processes) | about 0.10 cores (capacity audit) | 14 s, 0.12 cores |
| `core` CPU over 120 s | | 5 s, 0.04 cores |

The first service count after the second activation read 455 services and 66 hosts for about 40 seconds (the core reloading), then 599 and 83.

**Time to DOWN (controlled outage, 2026-10-28 23:39:11 to 23:39:41 CET).** On `monitoring1` and `monitoring2` a blackhole route for `8.8.8.8` (`ip route add blackhole 8.8.8.8/32`) was set at the same epoch second (1793227151, both containers within 8 ms) and removed after 30 seconds. `google-dns` has a 1-second Smart Ping in both sites and no TCP traffic that could count as a sign of life. From `lq "GET log"`:

| Site | DOWN logged | Plugin output | UP logged |
| --- | --- | --- | --- |
| `core` | 23:39:17 | No IP packet received for 3.512383 s (deadline is 2.500000 s) | 23:39:41 |
| `prod_k8s` | 23:39:17 | No IP packet received for 3.244336 s (deadline is 2.500000 s) | 23:39:42 |

Both sites report DOWN in the same second, 6 seconds after the block started, and UP within 1 second after it ended. The plugin output names a gap of 3.2 to 3.5 seconds; the difference to the 6 seconds is not explained (the log has a resolution of one second). `prod_k8s` created host notifications, but "1 rules matched, but no notification has been created", so nothing was sent. The Nagios host in `free` stayed UP (its 1-minute check did not fall into the window); the blackhole routes are gone on both containers.

## Not yet done

- Parallel run of a few days, compare DOWN and UP times of the ten hosts in `core` and `prod_k8s`.
- Stop `core`, then re-measure `prod_k8s` services (599), CPU of `prod_k8s` and `monitoring2`, memory of `monitoring1`, pve5 headroom.
