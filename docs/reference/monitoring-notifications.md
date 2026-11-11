---
status: current
---

# Monitoring notifications

**Status:** current as of 2026-11-11. First read from the live Checkmk configuration and alert history over read-only SSH on 2026-10-25 (`monitoring1`: `qa_k8s`; `monitoring2`: `prod_k8s`, `prod`), re-read on 2026-11-09 for stream B ([below](#stream-b-notifications-live)); rules applied through the REST API on 2026-11-11, see [Rules applied](#rules-applied-to-prod_k8s-and-prod-2026-11-11). The settings are click-ops in the Checkmk UI except where this page says they were done through the API, so this page is the only written record; if it and the live site disagree, the site wins and this page is stale.

**Tracking:** [#1893](https://github.com/isejalabs/homelab/issues/1893) (this page), [#1892](https://github.com/isejalabs/homelab/issues/1892) (`unifi` namespace fix), [#2158](https://github.com/isejalabs/homelab/issues/2158) (stream B, notifications live), umbrella [#71](https://github.com/isejalabs/homelab/issues/71).

Scope: notification settings and the noise of the Kubernetes sites. Other alert clean-up before notifications can go live on `prod` (thresholds [#1847](https://github.com/isejalabs/homelab/issues/1847), monitoring disks [#1843](https://github.com/isejalabs/homelab/issues/1843), Longhorn API hosts [#1846](https://github.com/isejalabs/homelab/issues/1846), `sssd`/`nullmailer` [#1848](https://github.com/isejalabs/homelab/issues/1848)) is tracked there, not here.

What fires a notification, when, and why that is (not yet) a good signal-to-noise ratio (SNR). Site inventory is in [`monitoring-sites.md`](monitoring-sites.md).

## Notification settings per site

| Site | Notifications | Service notification delay | Notification period | Periodic discovery |
| --- | --- | --- | --- | --- |
| `qa_k8s` | **on** (mail and Slack) | 15 min for all services (rule "Delay all service notifications by 15m"); 60 min for `Check_MK Discovery`, none for `Check_MK HW/SW Inventory` (since 2026-10-25, [#1900](https://github.com/isejalabs/homelab/issues/1900)) | none (24x7) | every 5 min, auto-rediscovery after 15 min grouping |
| `dev_k8s` | off in effect: default mail rule, but the contact has no mail address, so every mail fails | none | none | |
| `prod_k8s` | off in effect: default mail rule, but the contact has no mail address, so every mail fails | delays and ownership rules applied 2026-11-11 (same shape as `qa_k8s`, plus the 2 min Smart Ping host delay and the Talos-node disable); still fails to send until a method exists | none | every 33 min, auto-rediscovery after 15 min grouping |
| `prod` | off: no notification rule, and the contact `bob` has notifications disabled | delays and the Smart Ping host-disable rule applied 2026-11-11; still off until the contact gets a method | `p5-22` (05:00–22:00, every day) for hosts and services; `APT Updates` uses `p_reg_wo_apt` (11:20–22:00) | every 125 min for `tcp`-tagged hosts, adds new services only |

"Off" is not the global switch: the core's `enable_notifications` is on in every site. On `dev_k8s` and `prod_k8s` the raw notifications reach the mail rule and fail there (`notify.log`: "Cannot send HTML email: empty destination email address", 411 times on `dev_k8s` in the 14 days to 2026-11-09). Setting a mail address or a push rule on one of these contacts is now safe to do in any order: the delay and ownership rules are live on both `prod_k8s` and `prod` as of 2026-11-11, before either contact can send anything.

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

`qa_k8s` notifies today for its Talos nodes (confirmed live: `qa-ctrl-02`, `qa-work-01..03` carry the same `cmk/kubernetes/object:node` label as `prod_k8s`'s nodes); D2 moves them to `prod`. `prod_k8s`'s own node-disable rule is applied (see [below](#rules-applied-to-prod_k8s-and-prod-2026-11-11)); `qa_k8s`'s matching rule is deliberately held back until `prod` can actually notify for Talos nodes, so applying it now would leave `qa`'s nodes notifying from neither site.

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
| Delay host notifications | the twelve Smart Ping hosts | 2 min (owner, 2026-11-11) | `prod_k8s` | rule in place (`first_notification_delay=2` on the host chain); not yet exercised by a real outage |

The capacity delay of 0 min is cheap: 12 capacity episodes on `prod` in 14 days, all longer than 15 min. Mind that five `Filesystem /` services of Talos nodes and `monitoring2`'s are CRIT right now through the time-left levels (60 days left, CRIT below 70), so they push as soon as a push method exists ([#1908](https://github.com/isejalabs/homelab/issues/1908), [#1843](https://github.com/isejalabs/homelab/issues/1843)).

**Held back, deliberately, not applied yet:**

- **`qa_k8s`'s Talos-node disable rule.** It only makes sense once `prod` actually notifies for Talos nodes (a mail address or push rule on `prod`'s contact, not merely the rules existing) — applying it now would leave `qa`'s nodes notifying from neither site. Apply it in the same change as giving `prod`'s contact a working method.
- **`prod`'s Kubernetes-object/cluster-collector folder rule.** The D2 decision also has `prod` turn off notifications for its `k8s/ends` (namespaces, Deployments) and `k8s/piggys` (cluster collector) hosts, but unlike the Talos-node rule above this has no `cmk/kubernetes/object:node`-style label to condition on cleanly from the root folder — it needs either a rule placed directly in each of those two folders (relying on Checkmk's folder-recursion scoping, unverified live) or a label-group condition combining "is a Kubernetes object" and "is not a node", which I have not verified against the live label set. Not applied to avoid a half-verified write to a live site; `prod`'s own contact is still off today, so there is no live exposure from leaving this open. Needs the same care (dry run, live read-back) as the rules above before it goes in.

Both gaps are inert today: `prod`'s contact has no working notification method yet, so nothing from either folder notifies from `prod` regardless of these rules.

Pushover and mail rules themselves still need to be created once the account and 1Password item exist (see [Steps for the owner](#steps-for-the-owner)):

1. **Push:** method Pushover, contact `bob`; host events DOWN and UP of the Smart Ping hosts (`prod_k8s`); service events to CRIT and back of the capacity services above (both sites). Priority high for problems, normal for recoveries.
2. **Mail:** the existing default HTML mail rule (host `d`/`r`, service `c`/`w`/`r`), with the address set on contact `bob`.

### `prod` is not ready for service notifications

Replayed against the rules above, `prod` would send about 600 notifications in 14 days (outside the `p5-22` period fewer). The largest sources: host checks of the external probes in folder `external_sites` (`www.heise.de`, `mailbox.rollernet.us`, `gw-kdg`, `google-dns`: about 9 short DOWNs a day each; the last two are covered by Smart Ping), `Interface wifi1ap5` (87), `APT Updates` (69), the host checks in folder `misc` (57, mostly `pi3` and `pi4`), `NTP Time` (43), `Systemd Service Summary` (26, the failed `borgmatic` unit on `pve1`/`pve4`), `Memory` and `Temperature Zone 8` on physical hosts (17 each) and `Check_MK` on Talos nodes (21). That clean-up is the `prod` counterpart of [#1901](https://github.com/isejalabs/homelab/issues/1901) and comes before switching the contact on.

### Steps for the owner

The delay and ownership rules above are already live on `prod_k8s` and `prod` (2026-11-11), so these steps are safe to do in any order from here:

1. Pushover: create the account (30-day trial, then USD 4.99 per platform), install the app, create an application named Checkmk. Store the API key and the user key in a 1Password item — see [1Password item format](#1password-item-format) below for the exact item/field names expected when wiring the keys into the push rule.
2. Create the push rule on `prod_k8s` and `prod` (Pushover, contact `bob`) and set the mail address on contact `bob` (`qa_k8s` already has it).
3. Test the delivery with Setup > Notifications > Test notifications (host `google-dns`, state DOWN): the push must arrive on the phone.
4. Controlled outage of one WAN target, reversible and local to `monitoring2`: as root in the container, `iptables -I OUTPUT -d 8.8.8.8 -p icmp -j DROP`; wait for the DOWN push (seconds plus the 2 min host delay); `iptables -D OUTPUT -d 8.8.8.8 -p icmp -j DROP`; wait for the UP push. Only ICMP from the monitoring container to that address is dropped; DNS uses the internal resolvers.
5. Once `prod`'s contact has a working method, apply `qa_k8s`'s held-back Talos-node disable rule and `prod`'s held-back Kubernetes-object/cluster-collector folder rule (both described [above](#rules-applied-to-prod_k8s-and-prod-2026-11-11)).

#### 1Password item format

The 1Password CLI was not signed into the agent session, so this was not checked against the vault directly — check by hand that `checkmk-pushover` doesn't already exist before creating it. Following the `K8S` vault's existing `<thing>#<env>` naming for Checkmk-adjacent items (`checkmk-monitoring#<env>`, see [`terragrunt/README.md`](../../terragrunt/README.md#verifying-a-rustfs-monitoring-identity)) minus the `#<env>` suffix, since one Pushover destination serves every site, not one per environment:

| Item | Field | Value |
| --- | --- | --- |
| `checkmk-pushover` in vault `K8S` | `API_KEY` | the Pushover application's API token (30-40 alphanumeric characters) |
| | `RECIPIENT_KEY` | the Pushover user or group key to receive the notifications (30-40 alphanumeric characters) — named to match Checkmk's own `recipient_key` rule parameter |

The mail address for contact `bob` is a separate question: `qa_k8s` already has one set, so it likely already exists somewhere as a 1Password item rather than needing a new one — check what `qa_k8s`'s contact uses today before creating an `EMAIL` field on the item above or elsewhere. Never written into this file, an issue, a PR or a plan: only the item/field names above, never the key or address values themselves.

## Open questions

- Should `prod_k8s` get a night period like `prod`'s `p5-22`, or is the delay enough?
- How to keep performance problems visible without paging, for example a dashboard or a daily summary instead of a notification; no notification in the `qa_k8s` window was tied to the backup run, so load-related alerts have not been a problem so far.
