---
status: current
---

# Monitoring notifications

**Status:** current as of 2026-11-09. First read from the live Checkmk configuration and alert history over read-only SSH on 2026-10-25 (`monitoring1`: `qa_k8s`; `monitoring2`: `prod_k8s`, `prod`), re-read on 2026-11-09 for stream B ([below](#stream-b-notifications-live)). The settings are click-ops in the Checkmk UI, so this page is the only written record; if it and the live site disagree, the site wins and this page is stale.

**Tracking:** [#1893](https://github.com/isejalabs/homelab/issues/1893) (this page), [#1892](https://github.com/isejalabs/homelab/issues/1892) (`unifi` namespace fix), [#2158](https://github.com/isejalabs/homelab/issues/2158) (stream B, notifications live), umbrella [#71](https://github.com/isejalabs/homelab/issues/71).

Scope: notification settings and the noise of the Kubernetes sites. Other alert clean-up before notifications can go live on `prod` (thresholds [#1847](https://github.com/isejalabs/homelab/issues/1847), monitoring disks [#1843](https://github.com/isejalabs/homelab/issues/1843), Longhorn API hosts [#1846](https://github.com/isejalabs/homelab/issues/1846), `sssd`/`nullmailer` [#1848](https://github.com/isejalabs/homelab/issues/1848)) is tracked there, not here.

What fires a notification, when, and why that is (not yet) a good signal-to-noise ratio (SNR). Site inventory is in [`monitoring-sites.md`](monitoring-sites.md).

## Notification settings per site

| Site | Notifications | Service notification delay | Notification period | Periodic discovery |
| --- | --- | --- | --- | --- |
| `qa_k8s` | **on** (mail and Slack) | 15 min for all services (rule "Delay all service notifications by 15m"); 60 min for `Check_MK Discovery`, none for `Check_MK HW/SW Inventory` (since 2026-10-25, [#1900](https://github.com/isejalabs/homelab/issues/1900)) | none (24x7) | every 5 min, auto-rediscovery after 15 min grouping |
| `dev_k8s` | off in effect: default mail rule, but the contact has no mail address, so every mail fails | none | none | |
| `prod_k8s` | off in effect: default mail rule, but the contact has no mail address, so every mail fails | none | none | every 33 min, auto-rediscovery after 15 min grouping |
| `prod` | off: no notification rule, and the contact `sebi` has notifications disabled | none | `p5-22` (05:00–22:00, every day) for hosts and services; `APT Updates` uses `p_reg_wo_apt` (11:20–22:00) | every 125 min for `tcp`-tagged hosts, adds new services only |

"Off" is not the global switch: the core's `enable_notifications` is on in every site. On `dev_k8s` and `prod_k8s` the raw notifications reach the mail rule and fail there (`notify.log`: "Cannot send HTML email: empty destination email address", 411 times on `dev_k8s` in the 14 days to 2026-11-09). So setting a mail address on one of these contacts switches notifications on at once, without any delay rule; apply the delays first.

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

Recommendation (needs the owner, since the acceptance item says "no delay"): **2 minutes host notification delay for the Smart Ping hosts.** Detection stays at seconds, the push arrives two minutes into an outage, and a WAN failure is one incident instead of dozens. Parents (the WAN targets behind `gw-kdg`) would turn three of the four pushes of one WAN incident into UNREACHABLE, which the rule below does not send; only worth it if the topology really is that simple.

### Hosts in more than one site (D2)

Matched by host name across `prod`, `prod_k8s`, `qa_k8s` and `dev_k8s` (`core` is stopped):

| Group | Hosts | Sites | Who notifies (D2) |
| --- | --- | --- | --- |
| Smart Ping hosts | `gw`, `gw2`, `gw3`, `gw4`, `gw-kdg`, `google-dns`, `sw01`, `core-switch`, `ap-wozi`, `ap-kueche` (12 in `prod_k8s`, these 10 also in `prod`) | `prod_k8s` (Smart Ping), `prod` (SNMP, interfaces, `check_icmp`) | Host state: `prod_k8s`. Services: `prod` (`prod_k8s` only checks `PING`). |
| Talos nodes | `prod-ctrl-01..03`, `prod-work-01..03`; `qa-ctrl-02`, `qa-work-01..03`; `dev-ctrl-01`, `dev-work-01..03` | `prod`, plus the cluster's `*_k8s` site | `prod` |
| Kubernetes objects | 24 namespaces and Deployments (15 of `prod`, 7 of `dev`, 2 of `qa`), plus the three cluster collector hosts | `prod`, plus the cluster's `*_k8s` site | Open, see [below](#where-kubernetes-objects-notify-from-d2) |

`qa_k8s` notifies today for its Talos nodes; D2 moves them to `prod`, so `qa_k8s` needs the same node rule as `prod_k8s` once `prod` notifies.

### Where Kubernetes objects notify from (D2)

What each site sees of the `prod` cluster:

| | `prod` (Kubernetes special agent) | `prod_k8s` |
| --- | --- | --- |
| Objects | 5 Deployments, 10 namespaces (a hand-picked subset), 1 cluster host | 40 Deployments, 10 DaemonSets, 1 StatefulSet, 20 namespaces, 1 cluster host |
| `Replicas` services | 5 | 51 |
| Service episodes on objects, 14 days | 4, objects of all clusters (3 last ≥ 15 min) | 24 (1 lasts ≥ 15 min) |
| Cluster host episodes, 14 days | 13 (8 ≥ 15 min) | 34 (0 ≥ 15 min) |

Noise is no argument either way: with the 15 min delay both sites would send about one notification a fortnight for Kubernetes objects. Coverage is: `prod` sees a tenth of the workloads.

Recommendation (for the owner to confirm): **Kubernetes objects notify from the `*_k8s` site of their cluster** (`prod_k8s` for `prod`, `qa_k8s` for `qa`, none for `dev`), and `prod` turns notifications off for its Kubernetes object and cluster collector hosts (folders `k8s/ends` and `k8s/piggys`). Reasons: full workload coverage today instead of 5 of 51 `Replicas`; `prod_k8s` notifies anyway for Smart Ping, so no extra site sends; widening `prod`'s object set to match would add piggyback hosts to the site that stream D is trying to unload. Revisit when Prometheus takes over the fine-grained part (D4): the alerts move with the data. The alternative, `prod` for everything, needs `prod`'s special agent to import every Deployment, DaemonSet and StatefulSet first.

### Rules prepared for `prod_k8s` and `prod` (not applied)

Same shape as on `qa_k8s`, in this order (first match wins), at the root folder. Applying them was blocked in the agent session; the owner applies them in the UI or approves the REST call ([#2158](https://github.com/isejalabs/homelab/issues/2158)).

| Ruleset | Condition | Value | Sites |
| --- | --- | --- | --- |
| Delay service notifications | service `Check_MK Discovery$` | 60 min | both |
| Delay service notifications | service begins with `Filesystem`, `zpool`, `Storage Pool`, `Proxmox VE Storage`, `RustFS bucket`, `Longhorn disk`, `PVC ` | 0 min | both |
| Delay service notifications | all | 15 min | both |
| Enable/disable notifications for services | service `Check_MK HW/SW Inventory$` | disable | both |
| Enable/disable notifications for hosts and for services | host label `cmk/kubernetes/object:node` | disable | `prod_k8s` (D2) |
| Enable/disable notifications for hosts | the ten Smart Ping hosts that also exist in `prod` | disable | `prod` (D2) |
| Delay host notifications | the twelve Smart Ping hosts | 2 min, if the owner agrees | `prod_k8s` |

The capacity delay of 0 min is cheap: 12 capacity episodes on `prod` in 14 days, all longer than 15 min. Mind that five `Filesystem /` services of Talos nodes and `monitoring2`'s are CRIT right now through the time-left levels (60 days left, CRIT below 70), so they push as soon as the push rule is live ([#1908](https://github.com/isejalabs/homelab/issues/1908), [#1843](https://github.com/isejalabs/homelab/issues/1843)).

Notification rules, once the keys and the address exist (UI: Setup > Notifications):

1. **Push:** method Pushover, contact `sebi`; host events DOWN and UP of the Smart Ping hosts (`prod_k8s`); service events to CRIT and back of the capacity services above (both sites). Priority high for problems, normal for recoveries.
2. **Mail:** the existing default HTML mail rule (host `d`/`r`, service `c`/`w`/`r`), with the address set on contact `sebi`.

### `prod` is not ready for service notifications

Replayed against the rules above, `prod` would send about 600 notifications in 14 days (outside the `p5-22` period fewer). The largest sources: host checks of the external probes in folder `external_sites` (`www.heise.de`, `mailbox.rollernet.us`, `gw-kdg`, `google-dns`: about 9 short DOWNs a day each; the last two are covered by Smart Ping), `Interface wifi1ap5` (87), `APT Updates` (69), the host checks in folder `misc` (57, mostly `pi3` and `pi4`), `NTP Time` (43), `Systemd Service Summary` (26, the failed `borgmatic` unit on `pve1`/`pve4`), `Memory` and `Temperature Zone 8` on physical hosts (17 each) and `Check_MK` on Talos nodes (21). That clean-up is the `prod` counterpart of [#1901](https://github.com/isejalabs/homelab/issues/1901) and comes before switching the contact on.

### Steps for the owner

1. Pushover: create the account (30-day trial, then USD 4.99 per platform), install the app, create an application named Checkmk. Store the API key and the user key in 1Password.
2. Enter both keys in the push rule on `prod_k8s` (and on `prod` for capacity) and set the mail address on contact `sebi` (from 1Password; `qa_k8s` already has it), only **after** the delay rules are active.
3. Test the delivery with Setup > Notifications > Test notifications (host `google-dns`, state DOWN): the push must arrive on the phone.
4. Controlled outage of one WAN target, reversible and local to `monitoring2`: as root in the container, `iptables -I OUTPUT -d 8.8.8.8 -p icmp -j DROP`; wait for the DOWN push (seconds plus the host delay); `iptables -D OUTPUT -d 8.8.8.8 -p icmp -j DROP`; wait for the UP push. Only ICMP from the monitoring container to that address is dropped; DNS uses the internal resolvers.

## Open questions

- Should `prod_k8s` get a night period like `prod`'s `p5-22`, or is the delay enough?
- How to keep performance problems visible without paging, for example a dashboard or a daily summary instead of a notification; no notification in the `qa_k8s` window was tied to the backup run, so load-related alerts have not been a problem so far.
