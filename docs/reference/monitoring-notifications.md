---
status: current
---

# Monitoring notifications

**Status:** current as of 2026-10-25. Read from the live Checkmk configuration and alert history over read-only SSH on that date (`monitoring1`: `qa_k8s`; `monitoring2`: `prod_k8s`, `prod`). The settings are click-ops in the Checkmk UI, so this page is the only written record; if it and the live site disagree, the site wins and this page is stale.

**Tracking:** [#1893](https://github.com/isejalabs/homelab/issues/1893) (this page), [#1892](https://github.com/isejalabs/homelab/issues/1892) (`unifi` namespace fix), umbrella [#71](https://github.com/isejalabs/homelab/issues/71).

What fires a notification, when, and why that is (not yet) a good signal-to-noise ratio (SNR). Site inventory is in [`monitoring-sites.md`](monitoring-sites.md).

## Notification settings per site

| Site | Notifications | Service notification delay | Notification period | Periodic discovery |
| --- | --- | --- | --- | --- |
| `qa_k8s` | **on** | 15 min for all services (rule "Delay all service notifications by 15m") | none (24x7) | every 5 min, auto-rediscovery after 15 min grouping |
| `prod_k8s` | off | none | none | every 33 min, auto-rediscovery after 15 min grouping |
| `prod` | off | none | `p5-22` (05:00–22:00, every day) for hosts and services; `APT Updates` uses `p_reg_wo_apt` (11:20–22:00) | every 125 min for `tcp`-tagged hosts, adds new services only |

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
| `Replicas` | 43 | 10 | Mostly roll-outs under 15 min (filtered); the long ones are real (for example `unbound` 1/2 ready for 11 h) |
| `Memory` | 24 | 17 | **Signal**: `Committed` above 100 % on `qa-ctrl-02` and `qa-work-02` for hours; a sizing issue |
| `CPU`, `Filesystem` | 9, 8 | 6, 4 | Signal, on `qa-work-02` and `/` near the 80 % threshold |
| `Kubelet`, `Kubernetes API`, `Cluster collector` | 25, 8, 11 | 0, 0, 2 | Short blips filtered; a 94 min collector outage on 2026-10-23 was real |

No notification in the window was tied to the backup run or to other load: the `Memory`/`CPU`/`Filesystem` episodes are spread over the day and the same nodes, not clustered at a job time. Whether load spikes deserve a notification at all is undecided (see [open questions](#open-questions)).

### Unifi namespace owned by two Flux Kustomizations

`k8s/apps/network/unifi-controller/base/ns.yaml` and `k8s/apps/network/unifi-mongodb/base/ns.yaml` both define `Namespace/unifi`. Each Flux `Kustomization` stamps its own name into the label `kustomize.toolkit.fluxcd.io/name` when it reconciles (hourly), so the label alternates between `unifi-controller` and `unifi-mongodb`. Checkmk imports that label as a host label of `namespace_<cluster>_unifi`, sees a "new" and a "vanished" host label, and `Check_MK Discovery` goes WARN until auto-rediscovery fixes it. This is 253 of 372 `Check_MK Discovery` episodes on `qa_k8s` and 50 of 60 on `prod_k8s`, and is a flap that hides nothing real, so it is fixed at the source (one owner for the namespace), not by a notification rule.

### Discovery heals itself but notifies anyway

Both k8s sites use `update_everything` auto-rediscovery with a 900 s grouping time, so any new or changed object (a roll-out changes the version labels of a deployment) turns `Check_MK Discovery` WARN and Checkmk then fixes it 5–20 minutes later. The 15 min delay sits in the middle of that range, so about a third of these self-healing episodes still notify, typically right as they clear. The WARN carries no information that the auto-rediscovery did not already act on.

## Proposed changes (not applied)

Nothing below has been changed in Checkmk yet.

1. Fix the `unifi` namespace ownership in the repo ([#1892](https://github.com/isejalabs/homelab/issues/1892); the broader namespace layout question is [#1891](https://github.com/isejalabs/homelab/issues/1891)) (removes about two thirds of the `qa_k8s` Discovery noise and most of `prod_k8s`'s).
2. Give `Check_MK Discovery` a longer delay than the catch-all rule (for example 60 min, placed above it, since the first matching rule wins), so only a rediscovery that does not heal notifies.
3. Exclude `Check_MK HW/SW Inventory` from notifications (a once-a-day check cannot produce a timely signal).
4. Keep the 15 min catch-all delay and the unfiltered `Memory`/`CPU`/`Filesystem` notifications; consider flap detection or hysteresis for the threshold flappers instead of hiding them.
5. Before turning notifications on for `prod_k8s`: repeat 1–3 there, add the same catch-all delay, and align its periodic discovery interval. For `prod`, the existing `p5-22` period already pauses the night.

## Open questions

- Should `prod_k8s` get a night period like `prod`'s `p5-22`, or is the delay enough?
- How to keep performance problems visible without paging, for example a dashboard or a daily summary instead of a notification for `Memory`/`CPU` near thresholds.
- Does a repeated near-threshold flap (21 `Filesystem` episodes on `prod_k8s` in a week, 17 of them `/` on `prod-ctrl-01` hovering at 80 %) warrant its own rule?
