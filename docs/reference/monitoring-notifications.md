---
status: current
---

# Monitoring notifications

**Status:** current as of 2026-11-21. First read from the live Checkmk configuration and alert history over read-only SSH on 2026-10-25 (`monitoring1`: `qa_k8s`; `monitoring2`: `prod_k8s`, `prod`), re-read on 2026-11-09 for stream B ([below](#stream-b-notifications-live)); rules applied through the REST API on 2026-11-11, 2026-11-20 and 2026-11-21, see [Rules applied](#rules-applied-to-prod_k8s-and-prod-2026-11-11). Push is live via Pushover as of 2026-11-20 (owner confirmed delivery), including `prod_k8s`'s own capacity services since 2026-11-21. The owner ran the real, OPNsense-based outage test on 2026-11-21 ([below](#controlled-outage-test)) after local `iptables` attempts on `monitoring2` turned out not to work for how Smart Ping's check is built. **Mail is now live on `prod` too, since 2026-11-21, after a noise re-measurement and one clean-up rule** ([below](#prod-noise-clean-up-and-mail-rule-2026-11-21)). The settings are click-ops in the Checkmk UI except where this page says they were done through the API or by direct file edit (`qa_k8s`, no REST-capable automation user there; `prod`'s 2026-11-21 changes, see below), so this page is the only written record; if it and the live site disagree, the site wins and this page is stale.

**Tracking:** [#1893](https://github.com/isejalabs/homelab/issues/1893) (this page), [#1892](https://github.com/isejalabs/homelab/issues/1892) (`unifi` namespace fix), [#2158](https://github.com/isejalabs/homelab/issues/2158) (stream B, notifications live), [#2413](https://github.com/isejalabs/homelab/issues/2413) (`prod` noise clean-up and mail rule, post-merge follow-up of [PR #2292](https://github.com/isejalabs/homelab/pull/2292)), umbrella [#71](https://github.com/isejalabs/homelab/issues/71).

Scope: notification settings and the noise of the Kubernetes sites. Other alert clean-up before notifications can go live on `prod` (thresholds [#1847](https://github.com/isejalabs/homelab/issues/1847), monitoring disks [#1843](https://github.com/isejalabs/homelab/issues/1843), Longhorn API hosts [#1846](https://github.com/isejalabs/homelab/issues/1846), `sssd`/`nullmailer` [#1848](https://github.com/isejalabs/homelab/issues/1848)) is tracked there, not here.

What fires a notification, when, and why that is (not yet) a good signal-to-noise ratio (SNR). Site inventory is in [`monitoring-sites.md`](monitoring-sites.md).

## Notification settings per site

| Site | Notifications | Service notification delay | Notification period | Periodic discovery |
| --- | --- | --- | --- | --- |
| `qa_k8s` | **on** (mail and Slack); its Talos nodes stopped notifying 2026-11-20 (D2, moved to `prod`) | 15 min for all services (rule "Delay all service notifications by 15m"); 60 min for `Check_MK Discovery`, none for `Check_MK HW/SW Inventory` (since 2026-10-25, [#1900](https://github.com/isejalabs/homelab/issues/1900)) | none (24x7) | every 5 min, auto-rediscovery after 15 min grouping |
| `dev_k8s` | off in effect: default mail rule, but the contact has no mail address, so every mail fails | none | none | |
| `prod_k8s` | **on** (mail: the pre-existing default rule, host `d`/`r`/service `c`/`w`/`r`, now has a working address — confirmed, one real send 2026-11-20; **push**: Pushover — Smart Ping host DOWN/UP since 2026-11-20, capacity services (`Filesystem`/`PVC `/etc.) CRIT/recovery since 2026-11-21) | delays and ownership rules applied 2026-11-11 (same shape as `qa_k8s`, plus the 2 min Smart Ping host delay and the Talos-node disable) | none | every 33 min, auto-rediscovery after 15 min grouping |
| `prod` | **on** (mail: new default rule since 2026-11-21, host `d`/`r`/service `c`/`w`/`r`, same shape as `prod_k8s`'s; **push**: Pushover, capacity CRIT/recovery only, since 2026-11-20, narrowed from a broader rule that had already paged on interface flaps — see [below](#the-pushover-rule-had-no-service-filter-and-already-paged-2026-11-20)) | delays, the Smart Ping host-disable, the Kubernetes-object disable rules (2026-11-11/2026-11-20) and the `ap-wozi`/`ap-kueche` radio-interface disable (2026-11-21, see [below](#prod-noise-clean-up-and-mail-rule-2026-11-21)) | `p5-22` (05:00–22:00, every day) for hosts and services; `APT Updates` uses `p_reg_wo_apt` (11:20–22:00) | every 125 min for `tcp`-tagged hosts, adds new services only |

"Off" is not the global switch: the core's `enable_notifications` is on in every site. `dev_k8s`'s only rule still fails (`notify.log`: "Cannot send HTML email: empty destination email address", 411 times in the 14 days to 2026-11-09) — `prod_k8s` had the identical failure until an address was added to the contact at some point before 2026-11-20 (found while re-verifying this page, not something done as part of this stream's changes). No backlog risk: checked live, 0 hosts/services were in a non-OK, notification-eligible state at the time. `prod`'s contact also now has an address; its mail rule went live 2026-11-21, see [below](#prod-noise-clean-up-and-mail-rule-2026-11-21).

Details that are easy to get wrong:

- **`qa_k8s` delay is 15 minutes, not 5.** It is the Checkmk "first notification delay": a service must stay non-OK for 15 minutes (counted from the state change) before the first notification. A problem that clears sooner never notifies. Hosts have no delay.
- **The notification time in a mail is not the time the problem started.** A mail for `OK -> WARN` at 06:34 followed by `WARN -> OK` at 06:37 is a problem that began at about 06:19 and lasted 18 minutes. Read the start time from the alert history, not from the mail timestamp.
- **Some checks have their own time threshold on top.** `Replicas` turns WARN after 5 and CRIT after 10 minutes not ready, so with the 15 min delay a stuck rollout notifies after roughly 20 minutes.
- **`prod`'s quiet hours are 22:00–05:00**, not 22:00–06:00.
- **Recipients:** `qa_k8s` has the default HTML mail rule (host `d`/`r`, service `c`/`w`/`r`) and a Slack rule on user `cmkadmin`. The webhook lives in the site's `contacts.mk`; it is not recorded here.

## Signal and noise in `qa_k8s` (14 days to 2026-10-25)

Counted as episodes (a hard non-OK state until the next OK) per service type, with how many lasted long enough to pass the 15 min delay.

| Service | Episodes | ≥ 15 min | Verdict |
| --- | --- | --- | --- |
| `Check_MK Discovery`, namespace `unifi` | 253 | 97 | **Noise from a repo bug**, see [below](#unifi-namespace-owned-by-two-flux-kustomizations) |
| `Check_MK Discovery`, everything else | 119 | 41 | Noise: roll-outs, see [below](#discovery-heals-itself-but-notifies-anyway) |
| `Check_MK` (piggyback) | 178 | 9 | Filtered by the delay (median 1 min) |
| `Check_MK HW/SW Inventory` | 5 | 5 | **Noise**: runs once a day, so a WARN sticks for 24 h and always notifies |
| Everything else (`Replicas`, `Memory`, `CPU`, `Filesystem`, `Kubelet`, `Kubernetes API`, `Cluster collector`, …) | 142 | 39 | Out of scope here: short blips are filtered by the delay; threshold and capacity tuning is [#1847](https://github.com/isejalabs/homelab/issues/1847) |

### Unifi namespace owned by two Flux Kustomizations

`k8s/apps/network/unifi-controller/base/ns.yaml` and `k8s/apps/network/unifi-mongodb/base/ns.yaml` both define `Namespace/unifi`. Each Flux `Kustomization` stamps its own name into the label `kustomize.toolkit.fluxcd.io/name` when it reconciles (hourly), so the label alternates between `unifi-controller` and `unifi-mongodb`. Checkmk imports that label as a host label of `namespace_<cluster>_unifi`, sees a "new" and a "vanished" host label, and `Check_MK Discovery` goes WARN until auto-rediscovery fixes it. This is 253 of 372 `Check_MK Discovery` episodes on `qa_k8s` and 50 of 60 on `prod_k8s`, and is a flap that hides nothing real, so it is fixed at the source (one owner for the namespace), not by a notification rule.

### Discovery heals itself but notifies anyway

Both k8s sites use `update_everything` auto-rediscovery with a 900 s grouping time, so any new or changed object (a roll-out changes the version labels of a deployment) turns `Check_MK Discovery` WARN and Checkmk then fixes it 5–20 minutes later. The 15 min delay sits in the middle of that range, so about a third of these self-healing episodes still notify, typically right as they clear. The WARN carries no information that the auto-rediscovery did not already act on.

## Proposed changes (not applied)

Nothing below has been changed in Checkmk yet. Applying them on `qa_k8s` is [#1900](https://github.com/isejalabs/homelab/issues/1900), enabling notifications for `prod_k8s` is [#1901](https://github.com/isejalabs/homelab/issues/1901).

1. Fix the `unifi` namespace ownership in the repo ([#1892](https://github.com/isejalabs/homelab/issues/1892); the broader namespace layout question is [#1891](https://github.com/isejalabs/homelab/issues/1891)) (removes about two thirds of the `qa_k8s` Discovery noise and most of `prod_k8s`'s).
2. Give `Check_MK Discovery` a longer delay than the catch-all rule (for example 60 min, placed above it, since the first matching rule wins), so only a rediscovery that does not heal notifies.
3. Exclude `Check_MK HW/SW Inventory` from notifications (a once-a-day check cannot produce a timely signal).
4. Keep the 15 min catch-all delay for everything else and do not hide threshold flappers; tuning the thresholds themselves is [#1847](https://github.com/isejalabs/homelab/issues/1847).
5. Before turning notifications on for `prod_k8s`: repeat 1–3 there, add the same catch-all delay, and align its periodic discovery interval. For `prod`, the existing `p5-22` period already pauses the night.

## Stream B: notifications live

Work of [#2158](https://github.com/isejalabs/homelab/issues/2158), stream B of the [observability plan](../plans/2026-11-observability.md#b--notifications-live) (decisions D2 and D11). Read on 2026-11-09 over SSH (alert history: the 14 days before). Nothing below is applied on a site yet unless it says so.

### Push channel: Pushover works on the Community site

Pushover is available on `prod` (2.5.0p15.community), not only on the commercial editions: the notification script `share/check_mk/notifications/pushover` and its rule parameters (`cmk/gui/wato/_notification_parameter/_pushover.py`, registered unconditionally) ship with the Community build. Slack and PagerDuty ship there too, so the fallback order of D11 stays possible.

The API key and the user key are plain text fields of the notification rule's parameters; Pushover does not take them from the Password Store. They live in the site's `etc/check_mk/conf.d/wato/notification_parameter.mk`, with 1Password as the source of truth. The configuration export of stream G (D9) must mask `api_key` and `recipient_key` there.

### Smart Ping: "no delay" would page about 135 times a day

The twelve hosts in folder `ping-only` of `prod_k8s` (the plan says ten; the two access points are included) use `check-mk-host-smart`, one check attempt, no notification delay, no parents. Hard DOWN episodes in 14 days:

| Host | < 10 s | 10–60 s | 1–5 min | 5–15 min | ≥ 15 min |
| --- | ---: | ---: | ---: | ---: | ---: |
| `gw-kdg` (WAN) | 386 | 178 | 15 | 2 | 5 |
| `google-dns` (WAN) | 373 | 185 | 16 | 2 | 5 |
| `srv3` (WAN) | 164 | 50 | 5 | 2 | 3 |
| `srv3.vpn` | 4 | 1 | 1 | 0 | 2 |
| `gw4` | 150 | 12 | 1 | 0 | 0 |
| `core-switch` | 130 | 22 | 0 | 0 | 0 |
| `ap-wozi`, `ap-kueche` | 38 | 3 | 0 | 0 | 0 |
| `gw`, `gw2`, `gw3`, `sw01` (each) | 38 | 0 | 0 | 0 | 0 |

The LAN hosts drop all at once for 3 to 10 seconds, about three times a day, at times such as 02:00, 04:15 and 06:00 ("No IP packet received for 9.4 s, deadline 2.5 s"). That points at the monitoring container stalling (for example a backup snapshot), not at the network; not verified. The WAN targets also flap for seconds many times a day, and really fail together for hours (for example 2026-11-02 19:53 for about 25 hours).

Host notifications per 14 days for a host notification delay on the Smart Ping hosts (an incident merges the hosts that are down at the same time):

| Delay | Host notifications | Incidents |
| ---: | ---: | ---: |
| none | 1908 | 128 |
| 30 s | 97 | 19 |
| 1 min | 59 | 14 |
| **2 min** | **43** | **9** |
| 5 min | 21 | 5 |

**Decided (owner, 2026-11-11): 2 minutes host notification delay for the Smart Ping hosts**, instead of the literal "no delay" of the original acceptance wording. Detection stays at seconds, the push arrives two minutes into an outage, and a WAN failure is one incident instead of dozens. Parents (the WAN targets behind `gw-kdg`) would turn three of the four pushes of one WAN incident into UNREACHABLE, which the rule below does not send; worth adding only if the topology really is that simple.

### Hosts in more than one site (D2)

Matched by host name across `prod`, `prod_k8s`, `qa_k8s` and `dev_k8s` (`core` is stopped):

| Group | Hosts | Sites | Who notifies (D2) |
| --- | --- | --- | --- |
| Smart Ping hosts | `gw`, `gw2`, `gw3`, `gw4`, `gw-kdg`, `google-dns`, `sw01`, `core-switch`, `ap-wozi`, `ap-kueche` (12 in `prod_k8s`, these 10 also in `prod`) | `prod_k8s` (Smart Ping), `prod` (SNMP, interfaces, `check_icmp`) | Host state: `prod_k8s`. Services: `prod` (`prod_k8s` only checks `PING`). |
| Talos nodes | `prod-ctrl-01..03`, `prod-work-01..03`; `qa-ctrl-02`, `qa-work-01..03`; `dev-ctrl-01`, `dev-work-01..03` | `prod`, plus the cluster's `*_k8s` site | `prod` |
| Kubernetes objects | 24 namespaces and Deployments (15 of `prod`, 7 of `dev`, 2 of `qa`), plus the three cluster collector hosts | `prod`, plus the cluster's `*_k8s` site | The cluster's `*_k8s` site, decided 2026-11-11, see [below](#where-kubernetes-objects-notify-from-d2) |

`qa_k8s` notified for its Talos nodes until 2026-11-20 (confirmed live: `qa-ctrl-02`, `qa-work-01..03` carry the same `cmk/kubernetes/object:node` label as `prod_k8s`'s nodes); D2 moves them to `prod`. All three node-disable rules (`prod_k8s`, `qa_k8s`, and `prod`'s Kubernetes-object/cluster-collector rule) are now applied — D2 is fully enforced, see [below](#rules-applied-to-prod_k8s-and-prod-2026-11-11).

### Where Kubernetes objects notify from (D2)

What each site sees of the `prod` cluster:

| | `prod` (Kubernetes special agent) | `prod_k8s` |
| --- | --- | --- |
| Objects | 5 Deployments, 10 namespaces (a hand-picked subset), 1 cluster host | 40 Deployments, 10 DaemonSets, 1 StatefulSet, 20 namespaces, 1 cluster host |
| `Replicas` services | 5 | 51 |
| Service episodes on objects, 14 days | 4, objects of all clusters (3 last ≥ 15 min) | 24 (1 lasts ≥ 15 min) |
| Cluster host episodes, 14 days | 13 (8 ≥ 15 min) | 34 (0 ≥ 15 min) |

Noise is no argument either way: with the 15 min delay both sites would send about one notification a fortnight for Kubernetes objects. Coverage is: `prod` sees a tenth of the workloads.

**Decided (owner, 2026-11-11): Kubernetes objects notify from the `*_k8s` site of their cluster** (`prod_k8s` for `prod`, `qa_k8s` for `qa`, none for `dev`), and `prod` turns notifications off for its Kubernetes object and cluster collector hosts (folders `k8s/ends` and `k8s/piggys`). Reasons: full workload coverage today instead of 5 of 51 `Replicas`; `prod_k8s` notifies anyway for Smart Ping, so no extra site sends; widening `prod`'s object set to match would add piggyback hosts to the site that stream D is trying to unload. Revisit when Prometheus takes over the fine-grained part (D4): the alerts move with the data. Recorded in the plan's D2 row ([`docs/plans/2026-11-observability.md`](../plans/2026-11-observability.md)).

### Rules applied to `prod_k8s` and `prod` (2026-11-11)

Applied through the Checkmk REST API as each site's own `terraform`/`automation` user (not WATO click-ops, so there is no WATO audit-log entry; this page is the record), created at the root folder in this order (first match wins, confirmed from the written `rules.mk` before activating) and activated. Read-only verification both before (rulesets were empty, 0 pending changes on each site) and after (the live service/host attributes below) confirmed the change.

| Ruleset | Condition | Value | Site | Live-verified |
| --- | --- | --- | --- | --- |
| Delay service notifications | service `Check_MK Discovery$` | 60 min | `prod_k8s`, `prod` | yes, `first_notification_delay=60` on a live `Check_MK Discovery` service |
| Delay service notifications | service begins with `Filesystem`, `zpool`, `Storage Pool`, `Proxmox VE Storage`, `RustFS bucket`, `Longhorn disk`, `PVC ` | 0 min | `prod_k8s`, `prod` | yes, `first_notification_delay=0` on `prod-ctrl-02`'s `Filesystem /` |
| Delay service notifications | all | 15 min | `prod_k8s`, `prod` | yes, correct rule-chain position (index 2, after the two rules above) |
| Enable/disable notifications for services | service `Check_MK HW/SW Inventory$` | disable | `prod_k8s`, `prod` | rule in place; no matching service exists on `prod` today to check against live, `qa_k8s` precedent confirms the mechanism |
| Enable/disable notifications for hosts and for services | host label `cmk/kubernetes/object:node` | disable | `prod_k8s` (D2) | yes, `notifications_enabled=0` on `prod-ctrl-01`'s host |
| Enable/disable notifications for hosts | the ten Smart Ping hosts that also exist in `prod` | disable | `prod` (D2) | yes, `notifications_enabled=0` on `gw-kdg`'s host |
| Delay host notifications | the twelve Smart Ping hosts | 2 min (owner, 2026-11-11) | `prod_k8s` | yes, `first_notification_delay=2` on `gw-kdg`'s host, confirmed 2026-11-20; exercised by a real outage 2026-11-21 (see [below](#controlled-outage-test)) |
| Enable/disable notifications for hosts and for services | host label `cmk/kubernetes/object:node` | disable | `qa_k8s` (D2, applied 2026-11-20) | yes, `notifications_enabled=0` on `qa-ctrl-02`'s host |
| Enable/disable notifications for hosts and for services | host label `cmk/kubernetes:yes` and not `cmk/kubernetes/object:node` | disable | `prod` (D2, applied 2026-11-20) | yes, `notifications_enabled=0` on `namespace_prod-homelab_whoami`'s host and all its services, and on the `cmk-k8s-cluster-collector.prod.iseja.net` host; `prod-ctrl-01` (a Talos node) unaffected at `notifications_enabled=1` |

The capacity delay of 0 min is cheap: 12 capacity episodes on `prod` in 14 days, all longer than 15 min. Mind that five `Filesystem /` services of Talos nodes and `monitoring2`'s are CRIT right now through the time-left levels (60 days left, CRIT below 70), so they push as soon as a push method exists ([#1908](https://github.com/isejalabs/homelab/issues/1908), [#1843](https://github.com/isejalabs/homelab/issues/1843)).

`qa_k8s`'s node-disable rule (2026-11-20) was applied by direct `rules.mk` edit over SSH, backed up first (`~/rules.mk.bak-2158-20261120` in the site's home on `monitoring1`) and validated as parsing Python before `cmk -O` reloaded the core — the same precedent as [#1900](https://github.com/isejalabs/homelab/issues/1900), since `qa_k8s` has no REST-capable automation user (only `agent_registration`, role-limited, and admins with no stored automation secret). `prod`'s Kubernetes-object rule used the REST API as usual; the label condition (`cmk/kubernetes:yes AND NOT cmk/kubernetes/object:node`) was confirmed live against a namespace, a Deployment and the cluster-collector host before writing the rule, and does not touch the Talos nodes (which keep notifying from `prod`).

### Pushover rules (applied 2026-11-20)

| Rule | Conditions | Site | Notes |
| --- | --- | --- | --- |
| Pushover: Smart Ping host DOWN/UP | host-only (no service matching at all); the twelve Smart Ping hosts; 24x7 | `prod_k8s` | New rule, created via the REST API, reusing the same Pushover credentials as the `prod` rule below. |
| Pushover notification | service-only (no host matching at all); `Filesystem`/`zpool`/`Storage Pool`/`Proxmox VE Storage`/`RustFS bucket`/`Longhorn disk`/`PVC `; CRIT and CRIT→OK recovery only (not WARN); 24x7 | `prod` | Narrowed from the owner's original manual rule — see below. |
| Pushover: `prod_k8s` capacity CRIT (Filesystem/PVC/etc.) | service-only (no host matching at all); same service list as the `prod` rule above; CRIT and CRIT→OK recovery only; 24x7 | `prod_k8s` | Added 2026-11-21 (owner: mail is not sufficient for `PVC`/filesystem, the most important checks). New rule, created via the REST API, reusing the same Pushover credentials as `prod_k8s`'s Smart Ping rule above (same `notify_plugin` UUID in `notifications.mk`, no new secret). The 0 min capacity delay was already live on `prod_k8s` since 2026-11-11 — only the push rule itself was missing. |

Both were verified against the actual written `notifications.mk`, not just the REST API's response: Checkmk's notification-rule schema silently fills in a *"match everything"* default for an omitted event-type condition rather than *"no restriction of this type"*, so the first version of the `prod_k8s` rule came back with `match_service_event` still present (`?r`, `?w`, `?c`) despite the host-only intent — caught by reading `rules.mk`, fixed by explicitly setting that condition's state to `disabled` rather than omitting it, and reconfirmed in the file afterward.

#### The Pushover rule had no service filter and already paged (2026-11-20)

The rule the owner created by hand in the UI (`prod`, id `f8fee61f-...`) had **no service condition at all** and matched every host DOWN/UP plus every service CRITICAL/WARNING/OK transition, restricted only to `p5-22` (05:00–22:00). Checking `notify.log`/the site's notification log confirmed it had already fired for real, not just in the test: `Interface wifi1ap4`/`wifi1ap5` CRITICAL/OK flaps on `ap-wozi` and `ap-kueche`, and a `Filesystem /` WARNING on `prod-ctrl-02`, all pushed to the phone on 2026-11-12 between 08:38 and 09:39. Narrowed via the REST API (read the live rule, keep the Pushover credentials, add the `match_services` condition with the capacity list, restrict `match_service_event_type` to CRIT/CRIT→OK only, and disable `match_host_event_type` and the time-period restriction entirely so push covers CRIT 24x7 per D11) and re-verified against `notifications.mk`.

### `prod` is not ready for service notifications

Replayed against the rules above, `prod` would send about 600 notifications in 14 days (outside the `p5-22` period fewer). The largest sources: host checks of the external probes in folder `external_sites` (`www.heise.de`, `mailbox.rollernet.us`, `gw-kdg`, `google-dns`: about 9 short DOWNs a day each; the last two are covered by Smart Ping), `Interface wifi1ap5` (87), `APT Updates` (69), the host checks in folder `misc` (57, mostly `pi3` and `pi4`), `NTP Time` (43), `Systemd Service Summary` (26, the failed `borgmatic` unit on `pve1`/`pve4`), `Memory` and `Temperature Zone 8` on physical hosts (17 each) and `Check_MK` on Talos nodes (21). That clean-up is the `prod` counterpart of [#1901](https://github.com/isejalabs/homelab/issues/1901) and comes before switching the contact on.

### `prod` noise clean-up and mail rule (2026-11-21)

Work of [#2413](https://github.com/isejalabs/homelab/issues/2413), the post-merge follow-up of [PR #2292](https://github.com/isejalabs/homelab/pull/2292) that left this one item open. Re-measured live (`GET log` over the site's `livestatus` socket, class 3 = notifications, the same table the REST API's `GET log` endpoint wraps), not estimated.

**The ~600/14d figure above was the pre-rule replay from 2026-11-09.** With the delay and D2 ownership rules of 2026-11-11 (and the Kubernetes-object disable of 2026-11-20) already live, the real current rate is far lower:

| Window | Raw log rows (class 3) | Notes |
| --- | --- | --- |
| 14 days to 2026-11-21 (unfiltered) | 671 `SERVICE NOTIFICATION` + 371 `HOST NOTIFICATION` | Contaminated by stale pre-rule data: every `HOST NOTIFICATION` for `gw-kdg`/`google-dns` dates 2026-11-07 to 2026-11-10, before their 2026-11-11 host-disable rule; `www.heise.de`/`mailbox.rollernet.us` host flapping likewise stopped entirely after 2026-11-11 for an unrelated reason, not investigated further here. |
| 2026-11-11 to 2026-11-21 (10 days, all 2026-11-11 rules + the 2026-11-20 Kubernetes-object rule live for part of the window) | 108 `SERVICE NOTIFICATION` + 2 `HOST NOTIFICATION` | The current steady-state rate: ≈150/14d scaled, not ≈600. The 2 host entries are `namespace_prod-homelab_whoami`, from before the 2026-11-20 Kubernetes-object disable rule. |
| 2026-11-20 to 2026-11-21 (all rules fully live) | 0 | Too short a window to extrapolate from alone, but consistent with the 10-day rate. |

Breakdown of the 108 service notifications since 2026-11-11, by `service_description`: `Interface wifi1ap5`/`wifi1ap4`/`wifi1ap6` (29, all on `ap-wozi`/`ap-kueche` — see below), ~40 from one `dev_k8s` site restart at 2026-11-17 ~21:46 UTC (21 processes/`OMD`/`Site` services on `monitoring1`, each CRIT→OK within about 10 minutes — a real event reported faithfully, not noise, and not a recurring pattern), `Memory` (8, `fiona`/`prod-work-01`), `NTP Time` (7, `fiona`/`polina`), `Filesystem /` and other capacity services (10, genuine, already tracked in [#1843](https://github.com/isejalabs/homelab/issues/1843)/[#1908](https://github.com/isejalabs/homelab/issues/1908), kept at 0 min delay by design per D11), `HTTPS hassos-prod.home.iseja.net` (5), `Check_MK`/`Check_MK Discovery` (3, already covered by the 60 min delay rule) and a handful of one-off singles.

**Clean-up applied: disabled service notifications for the `ap-wozi`/`ap-kueche` radio interfaces.** `Interface wifi1ap4`/`wifi1ap5`/`wifi1ap6`/`wifi1ap7` on these two access points flap repeatedly (WiFi roaming/interference, not an outage) — the exact noise that had already paged for real through the owner's hand-made Pushover rule before PR #2292 narrowed it (see [above](#the-pushover-rule-had-no-service-filter-and-already-paged-2026-11-20)). Host-level DOWN/UP for both already notifies from `prod_k8s` (Smart Ping, D2); this rule only silences the SNMP interface-level flapping on `prod`, reusing the same `extra_service_conf['notifications_enabled']` ruleset as the existing `Check_MK HW/SW Inventory` and Kubernetes-object disable rules.

| Ruleset | Condition | Value | Site | Live-verified |
| --- | --- | --- | --- | --- |
| Enable/disable notifications for services | host `ap-wozi.home.iseja.net`/`ap-kueche.home.iseja.net`, service regex `Interface wifi1ap` | disable | `prod` | yes, `notifications_enabled=0` on both hosts' `Interface wifi1ap4`–`wifi1ap7` services; `wifi0ap*`/`eth0*` interfaces on the same hosts and `prod-ctrl-01`'s `Check_MK` unaffected at `notifications_enabled=1` |

No other rule changes were made: `Memory`, `NTP Time` and the capacity services are modest-volume, mostly single episodes, and either already time-delayed or deliberately undelayed by design (capacity, D11) — plan decision stands (line 61 above) against hiding threshold flappers, and nothing else in the post-rule data repeats often enough to justify a new rule. The `dev_k8s`-restart burst is a real, informative event (one Checkmk site's own health), not something to suppress.

**Mail rule added**, same shape as `prod_k8s`'s pre-existing default rule: `notify_plugin: mail`, `match_host_event: ['d', 'r']`, `match_service_event: ['c', 'w', 'r']`, `contact_object: True` (routes to every host's assigned contact group, `sec.app.checkmk.operator`, same as `prod_k8s`), no time-period override (inherits each host/service's `p5-22` notification period, same as the rest of `prod`). No backlog risk from turning it on: Checkmk only notifies on a state *transition*, never retroactively for a steady pre-existing state, so turning mail on does not flood for problems that are already open — it only starts mailing on each one's *next* transition, at the same rate already measured above. A live snapshot at the time of the change did show roughly 120 hosts/services already non-OK with notifications enabled — chronic, already-tracked issues (`APT Updates`, `Temperature Zone`, several `pve4`/`pve1` SMART/Corosync services, a cluster of `pi4` filesystem/mount services under one stalled share, `borgbackup` jobs) covered by [#1843](https://github.com/isejalabs/homelab/issues/1843), [#1847](https://github.com/isejalabs/homelab/issues/1847) and [#1848](https://github.com/isejalabs/homelab/issues/1848), several of them in scheduled downtime at the time — not something this issue's scope cleans up, but worth knowing the first mails from `prod` may well be these recovering or re-alerting, not something newly broken.

**Method:** applied by direct `rules.mk`/`notifications.mk`/`notification_parameter.mk` edit over SSH as the site user (same precedent as `qa_k8s`'s 2026-11-20 rule, [#1900](https://github.com/isejalabs/homelab/issues/1900)), not the REST API `prod` otherwise uses — the working session for this issue had SSH access to `monitoring2` but not `prod`'s REST automation secret, so it fell back to the file-edit path rather than guess at credentials. Backed up first (`~/{rules,notifications,notification_parameter}.mk.bak-2413-20261121` in `prod`'s home), each edited file validated with `ast.parse` before `cmk -O` regenerated and reloaded the core (clean reload, no errors in `nagios.log`; `notify.log` empty before and after, since no notification-eligible transition has fired yet). Read back and confirmed matching what was intended before reloading, same as every other direct-edit or REST change on this page. A future change to `prod`'s notification rules should go through the REST API as usual, once that secret is available to whoever is making it.

### Controlled outage test

**Run for real by the owner on 2026-11-21, via OPNsense, per the procedure below: passed.** ICMP to `google-dns` (8.8.8.8) was blocked at 06:39; the host went DOWN and a notification arrived on both mail and Pushover at 06:41, inside the 2 min host delay. ICMP was re-enabled at 06:41, and the UP notification arrived at 06:42 — immediately, not after another 2 min wait. That's expected, not a bug: `first_notification_delay` only holds back the *first* notification after a problem is detected (so a blip that clears on its own within the window never pages); it has no effect on the recovery notification once the host (or service) actually returns to OK, since there's no reason to delay good news. Same behaviour applies to every other delay on this page, including the capacity CRIT delays.

Local attempts on `monitoring2` before this, for context on why the real test needed OPNsense:

Attempted on 2026-11-20 against `google-dns` (8.8.8.8) from `monitoring2`, reversible and local, as originally planned. Neither local `iptables` approach worked, for two different reasons, and both were fully reverted (confirmed: `iptables -S | grep 8.8.8.8` empty, host back to `state=0`, `is_flapping=0`):

1. **`iptables -I OUTPUT -d 8.8.8.8 -p icmp -j DROP`** (the originally documented approach): the Checkmk `icmpsender` process logged repeated `Could not send 64 bytes of ICMP data to 8.8.8.8: Operation not permitted` (`cmc.log`) — a netfilter DROP on a modern Linux "ping socket" surfaces as `EPERM` to the sender rather than a silent drop. That induced genuine check-level flapping (`HOST FLAPPING ALERT` fired on `google-dns`), and **Checkmk suppresses notifications while a host is flapping** — confirmed in `notify.log`: no `Got raw notification (google-dns)` entry appeared in the 7+ minutes the host stayed hard-DOWN, well past the 2 min delay, even though the `HOST ALERT` itself was logged correctly by the core.
2. **`iptables -I INPUT -s 8.8.8.8 -p icmp --icmp-type echo-reply -j DROP`** (blocking the reply instead, to avoid the `EPERM`): packets were confirmed matched and dropped (`iptables -L INPUT -n -v` showed a growing counter), yet the host kept reporting `state=0` with a fresh `last_check` throughout. Smart Ping's receive side almost certainly uses a raw `AF_PACKET` capture (the way `tcpdump`-style tools work), which taps packets at the device level *before* any `iptables` table — `raw`, `mangle` or `filter` — ever sees them, so no local netfilter rule on the `INPUT` side can affect what it sees either.

Neither approach exercises the real "no reply, ever" condition the Smart Ping check is actually built to detect; both local workarounds should be abandoned rather than refined further, since the next attempt would again be poking at the same raw-socket/packet-capture internals from inside the thing being tested. The task brief's own fallback applies: block at the real firewall instead, upstream of the monitoring container, where the packet never reaches `monitoring2` at all.

**Procedure the owner ran on OPNsense** (safer and more realistic than anything local, and the one actually used): temporarily add a firewall rule on the WAN-facing gateway blocking ICMP to `8.8.8.8` from `monitoring2`'s address, confirm the DOWN notification arrives within the 2 min delay, remove the rule, confirm the UP notification arrives. This exercises the real network path the Smart Ping check depends on, which the local test never did. Result: DOWN at 06:41 (block at 06:39), UP at 06:42 (re-enabled at 06:41), both mail and Pushover — see [above](#controlled-outage-test).

### Steps for the owner

The delay and ownership rules above are live on `prod_k8s` and `prod`; Pushover push is confirmed working, including the real outage test (owner, 2026-11-20/2026-11-21). Remaining:

1. ~~Pushover account, keys in 1Password~~ — done; keys read live from the existing rule, reused to build the `prod_k8s` host rule and the `prod_k8s` capacity rule below without re-entering them.
2. ~~Create the push rule on `prod_k8s` and `prod`~~ — done (narrowed on `prod`, created new on `prod_k8s` for Smart Ping and, since 2026-11-21, for its own capacity services too — see above).
3. ~~Test notification~~ — confirmed delivered (owner, 2026-11-20).
4. ~~Mail on `prod_k8s`~~ — already live (default rule, address on the contact, one real send confirmed in `notify.log`). ~~Mail on `prod`~~ — live since 2026-11-21, after the noise clean-up and re-measurement in [#2413](https://github.com/isejalabs/homelab/issues/2413) (see [above](#prod-noise-clean-up-and-mail-rule-2026-11-21)).
5. ~~The controlled outage test~~ — run via OPNsense, passed (owner, 2026-11-21, see above).

## Open questions

- Should `prod_k8s` get a night period like `prod`'s `p5-22`, or is the delay enough?
- How to keep performance problems visible without paging, for example a dashboard or a daily summary instead of a notification; no notification in the `qa_k8s` window was tied to the backup run, so load-related alerts have not been a problem so far.
