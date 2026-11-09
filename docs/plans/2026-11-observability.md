---
date: 2026-11-02
updated: 2026-11-09
status: Decisions D1 to D11 confirmed by the owner on 2026-11-09 (D3 and D11 revised, D10 amended); D2 still open for Kubernetes objects; issues restructured on 2026-11-02, see Tracking below; no stream started
scope: everything under https://github.com/isejalabs/homelab/issues/71 — Checkmk notifications, load and history, capacity checks, backup freshness, searchable logs with remote querying, log-derived alerts and the daily digest
supersedes: 2026-09-observability.md (Codex, tracked by phase issues) and 2026-09-observability-claude.md (Claude, comparison only); the September assessments in ../audits/ stay as they are
builds-on: 2026-10-checkmk-consolidation.md (https://github.com/isejalabs/homelab/issues/1783), which is done except its phase 4
tracking: https://github.com/isejalabs/homelab/issues/71
---

# Observability plan (reconciled)

## Why a new plan

The two September plans were written in parallel and never reconciled; only the Codex one has issues. Since then the work has moved on outside their phase tree: `free` was merged into `prod` and deleted, `core` was stopped, Smart Ping moved to `prod_k8s`, all sites run 2.5.0p15, and the Longhorn and RustFS capacity agents are live. Meanwhile the September ordering held back the things that matter most today:

- **Nothing notifies.** `prod` and `prod_k8s` have notifications off; only `qa_k8s` sends mail ([`monitoring-notifications.md`](../reference/monitoring-notifications.md)). Smart Ping detects an outage in about 6 seconds and tells no one. The September plans put alerting after the logging rollout.
- **Load is now concentrated in `prod` (Nagios):** 0.66 to 0.73 cores, 29 to 43 new processes per second, load average 9 to 16 on 3 vCPUs after the merge, CPU not lower than before ([merge result](../audits/2026-10-checkmk-free-merge-result.md)).
- **The SSD write gate was aimed at the wrong component.** The Proxmox SSDs take 250 to 300 GB/day ([#1596](https://github.com/isejalabs/homelab/issues/1596)); loghost writes about 42 MB/day. A log backend is well under 1% of the problem, so a week-long baseline before choosing one does not pay off.
- **Checkmk's own backup was never restored.** Phase 0's "Checkmk backups recoverable" is still open. The deleted `free` site now exists only in the Proxmox Backup Server backups of CT 7002056; PBS restores have been exercised for other VMs and LXCs, which the owner accepts as proof for this container too (2026-11-02).
- **The monitoring itself is at risk:** both monitoring containers' root disks were forecast full around 2026-11-22 ([#1843](https://github.com/isejalabs/homelab/issues/1843)), and `monitoring2` ran out of memory on 2026-10-18.

## Requirements, in priority order

1. **Fast outage detection with Smart Ping** for the network and WAN hosts (1 second, access points 6 seconds), and it must reach the owner as a push notification on the phone; mail alone is not read often enough.
2. **Low system load** on the monitoring containers and low incremental SSD writes on the Proxmox hosts.
3. Capacity WARN/CRIT and time-to-full for filesystems, ZFS, Longhorn disks and RustFS buckets; backup freshness.
4. Preserve the tiered RRD history (about 700 days, verified as up to four years in phase 0).
5. Searchable Kubernetes, Talos, Linux and appliance logs, queried from the workstation without SSH; authentication at least 90 days (likely longer, to be decided), applications and Events about 7 days (to be decided).
6. A few explicit log-derived alerts (OOM, repeated authentication failures, backup failures) and a grouped daily digest of unfamiliar messages.
7. €0 recurring cost preferred, at most €5/month. Salt for Linux hosts, Flux for Kubernetes, Terraform for API objects where it is already used, manual steps documented.

## Decisions

All decisions were confirmed by the owner on 2026-11-09. D3, D4, D6 and D11 come from the owner's own answers (2026-11-02, D3 and D11 revised on 2026-11-09), D10 was amended the same day. D2 is decided for hosts and Smart Ping and still open for Kubernetes objects.

| # | Decision | Reason |
| --- | --- | --- |
| D1 | Checkmk stays the system for metrics, capacity, history and **all notifications**, including log-derived ones. | One notification owner, existing RRDs and mail; no second alerting pipeline to maintain. |
| D2 | Each host notifies from **exactly one** site: Smart Ping hosts from `prod_k8s`, every other physical and virtual host (the Talos nodes included) from `prod`. **Open:** where Kubernetes objects notify from, decided in stream B. Either the `*_k8s` site of the cluster (it sees every object, down to pods) or `prod` (one tool for all notifications, but only the coarse objects it monitors). | Notifications are per site and never merged ([#1901](https://github.com/isejalabs/homelab/issues/1901)). |
| D3 | **`prod` is the long-term central site** (owner, 2026-11-09). It monitors every physical and virtual host, the Talos nodes included, and the near-static Kubernetes objects (namespaces, Deployments, StatefulSets, DaemonSets) of `dev`, `qa` and `prod` through its Kubernetes special agent, so the trends of CPU, memory and filesystems live there. The `*_k8s` sites (Ultimate today, possibly superseded by Prometheus) add what the Community edition does not provide: pod-level and finer-grained detail. `rebuild` leaves `prod`'s special agent (owner, 2026-11-02: `prod` does not need it) and gets a `rebuild_k8s` site for upgrade tests (stream I). | One query per cluster feeds all objects as piggyback data, so the Kubernetes checks in `prod` are cheap; keeping the trends in the central site lets the extra tool change without losing history. |
| D4 | Smart Ping stays in `prod_k8s`. When the site nears the 750-service limit (WARN 675, CRIT 713 already monitored), Kubernetes services are trimmed first (owner, 2026-11-02), starting with those that `prod` already covers (D3). If Checkmk's limits become the constraint for Kubernetes monitoring in general, Prometheus taking over the fine-grained Kubernetes part is the long-term alternative, not a ping-only site. | Keeps Smart Ping where it runs today and fewer sites, as decided on 2026-10-20. |
| D5 | Log store: **single-node VictoriaLogs on loghost** (two instances, see D6), fed by a copy of the syslog-ng stream, with the compressed file archive kept as fallback. No Loki pilot. | Native syslog intake, low RAM, an official CLI (`vlogscli`: query, live tail, JSON output, basic/bearer auth). The Loki comparison would cost weeks to decide a difference that is noise next to the host writes in [#1596](https://github.com/isejalabs/homelab/issues/1596). |
| D6 | **Two VictoriaLogs instances** on loghost (owner, 2026-11-02): one for authentication logs, one for application, Kubernetes and system logs, each with its own retention. Retention periods are decided in F2; authentication is likely longer than 90 days. syslog-ng routes authentication facilities and programs to the first instance and everything else to the second. | Retention is global per VictoriaLogs instance, so different periods need separate instances. |
| D7 | Budget for the whole logging addition, both instances and collectors included, fixed now: **≤ 1 GB/day incremental host writes, ≤ 512 MiB RAM, ≤ 0.2 cores average** on loghost's host. Measured once after rollout, not as a precondition. | Replaces the open-ended "agree a budget from a seven-day baseline" of phase 0. |
| D8 | Log-derived alerts become Checkmk services: a small special agent (`vlogs_query`) in [`isejalabs/checkmk-modules`](https://github.com/isejalabs/checkmk-modules) runs fixed LogsQL counts and maps them to thresholds. | Same pattern as `longhorn_capacity` and `rustfs_quota`; gets graphs, delays and notifications for free. The Checkmk Event Console is the alternative if a rule needs per-message state. |
| D9 | Terraform for Checkmk stays limited to the special-agent hosts, rules and Password Store entries. Everything else is captured by a nightly **read-only REST export** of folders, rules and notification settings into Git, instead of hand-kept rule ids in the reference docs. **Credential leak (owner, 2026-11-09):** the export fails closed. It runs as a read-only user and takes an allow-list of rule sets and host attributes, not everything. It replaces every secret-bearing value (passwords, SNMP communities, webhook URLs, API and user keys, contact addresses) with a placeholder and aborts on any value it cannot classify. A secret scanner runs before each commit, the first export is checked by hand against the secrets in 1Password, and the export goes to a **private** repository unless that check shows nothing sensitive is left. | The provider is v0.0.5 with one maintainer and was spiked on 2.4; the export gives a diffable record at no risk to the sites. Password Store entries are not returned by the REST API (Werk 13722); whether every inline password, SNMP community and notification parameter is masked is not verified, so the export must not rely on it. |
| D10 | Longhorn capacity and failure-mode checks read the Longhorn CRDs through the Kubernetes API with a read-only ServiceAccount token, not through the Longhorn UI route (owner, confirmed 2026-11-09). The UI route is protected by oauth2-proxy since [#2228](https://github.com/isejalabs/homelab/issues/2228) (operator and read-only access in [#2229](https://github.com/isejalabs/homelab/issues/2229)); monitoring keeps working there only through a skip-auth exception for `GET /v1/nodes`. | The CRD path gives the agent its own least-privilege identity, independent of the human SSO, so the skip-auth exception can be removed and [#1714](https://github.com/isejalabs/homelab/issues/1714) is solved; phase 0 already verified `nodes.longhorn.io` is readable that way. |
| D11 | **Push for urgent, mail for the rest.** Smart Ping DOWN, disk/quota CRIT and backup failures go to a push channel that reaches the phone; everything else goes by mail. Candidates, in order of preference (owner, 2026-11-09): **Pushover** (a notification method built into Checkmk; one-time USD 4.99 per platform, 30-day trial, 10,000 messages a month; its priority can override quiet hours), then Slack (already used by `qa_k8s`), then PagerDuty; choice in stream B. The mail address and any webhook, API or user key are secrets: kept in 1Password (and SOPS where Terraform needs them), never written in an issue, ADR, plan or reference doc. | E-mail is not read often enough for an outage; the repository and its issues are public. Pushover has no recurring cost, which fits the €0 preference. |

## Streams

Streams A to D are the infrastructure basics and come first; E and G can run alongside them; F is the logging work. Each stream keeps to three to five acceptance items.

### A — Keep the monitoring alive

Tracked in [#2157](https://github.com/isejalabs/homelab/issues/2157).

- [ ] Root disks of `monitoring1` and `monitoring2` have a known cause of growth and at least 90 days of forecast headroom ([#1843](https://github.com/isejalabs/homelab/issues/1843)).
- [ ] Each running site sends a heartbeat to healthchecks.io every few minutes (a Checkmk notification script or a cron job of the site user), so a stopped site, a dead container or a dead host alerts from outside the home network.
- [ ] One Checkmk site backup restored into an isolated site, with old graphs opened in the web interface (the open phase 0 item of [#1437](https://github.com/isejalabs/homelab/issues/1437)).

A restore of CT 7002056 from the Proxmox Backup Server is not needed: PBS restores are proven with other guests, which the owner accepts (2026-11-02).

### B — Notifications live

Tracked in [#2158](https://github.com/isejalabs/homelab/issues/2158).

- [ ] Push channel chosen (Pushover preferred, else Slack or PagerDuty, D11): availability of the method on the Community site `prod` checked, an app notification on the owner's phone shown to arrive for a test notification; the mail address and the keys stored as secrets only.
- [ ] `prod_k8s`: the ten Smart Ping hosts notify by push and mail on DOWN/UP with no delay, tested with a controlled outage of one WAN target.
- [ ] `prod_k8s` and `prod`: service notifications live with the delays settled in [#1900](https://github.com/isejalabs/homelab/issues/1900) (15 minutes catch-all, longer for `Check_MK Discovery`, none for `Check_MK HW/SW Inventory`), after the noise clean-up in [#1901](https://github.com/isejalabs/homelab/issues/1901) and the threshold work already done.
- [ ] Disk and quota CRIT notify by push without the catch-all delay.
- [ ] Every host notifies from exactly one site (D2), checked with a list of hosts that exist in more than one site.
- [ ] Decided and recorded: whether Kubernetes objects notify from the `*_k8s` sites or from `prod` (D2).

### C — Backup freshness

Tracked in [#2159](https://github.com/isejalabs/homelab/issues/2159).

- [ ] A matrix of every backup path with its freshness signal: kopiur, Longhorn recurring jobs, zrepl, borgbackup, Cloud Sync, and which of them healthchecks.io already covers.
- [ ] A Checkmk service for every path without a signal, CRIT when the last success is older than its schedule allows.
- [ ] zrepl replication to pi4 repaired and monitored ([#1905](https://github.com/isejalabs/homelab/issues/1905)); it has been broken since 2025-11 without any alert, which is the case this stream exists for.

### D — Lower the load of `prod`

Tracked in [#2160](https://github.com/isejalabs/homelab/issues/2160).

- [ ] A 24-hour per-command CPU profile of CT 7002056 (process accounting or cgroup sampling), ranking the Nagios checks, special agents and precompiled host checks.
- [ ] `prod`'s Kubernetes special agent no longer queries `rebuild` (D3); `dev`, `qa` and `prod` stay, since one query per cluster is cheap.
- [ ] The most expensive remaining items addressed from the profile, starting with the Proxmox special agent of `pve4` (36 to 40 seconds per run) and the forked `check_icmp` host checks of hosts that have an agent (switch to the `Check_MK`-status host check where Smart Ping already covers fast detection).
- [ ] Measured before and after on the Proxmox RRD of CT 7002056 against a trial target of 0.5 cores day average (today about 0.75); the owner could not judge the number up front, so the target is revisited with the profile's result rather than treated as fixed. This closes phase 4 of the consolidation plan.

### E — Finish the capacity checks

Tracked in [#1438](https://github.com/isejalabs/homelab/issues/1438), the remainder of phase 1A; the agents themselves are live.

- [ ] `longhorn_capacity` reads the CRDs through the Kubernetes API (D10); the Longhorn UI route is no longer used by monitoring, its skip-auth exception for `GET /v1/nodes` (from [#2228](https://github.com/isejalabs/homelab/issues/2228)) is removed, and [#1714](https://github.com/isejalabs/homelab/issues/1714) is closed.
- [ ] Values reconciled against the Longhorn UI, TrueNAS and RustFS for one known volume and one bucket; time-to-full shown where history is long enough, explicit "unknown" where it is not.
- [ ] Longhorn failure modes as services: faulted or degraded volumes, volumes stuck attaching, instance managers not running (the list on [#1441](https://github.com/isejalabs/homelab/issues/1441)).
- [ ] Daily USB backup-disk SMART and usage checks unchanged; no new spin-ups.

### F — Searchable logs, alerts and digest

Tracked in [#1439](https://github.com/isejalabs/homelab/issues/1439) (F1 to F3), [#1441](https://github.com/isejalabs/homelab/issues/1441) (F4, F5) and [#1440](https://github.com/isejalabs/homelab/issues/1440) (F6).

- **F1, loghost under Salt.** The syslog-ng and logcheck configuration of loghost lives in [`sebiklamar/salt-iseja.net`](https://github.com/sebiklamar/salt-iseja.net) and the host carries the `roles:loghost` grain; today Salt only installs the packages. Acceptance: a highstate on loghost is a no-op against the live configuration.
- **F2, VictoriaLogs.** Two instances (D6) installed on loghost by Salt, on their own volume, with syslog-ng sending each its share of what it receives; the file archive keeps running. Retention of both decided here, before ingest starts. Query access only through an authenticated reverse proxy on the LAN. Acceptance: `vlogscli` from the workstation runs a time-range search, a host filter, a JSON export and a live tail against both instances without SSH; an authentication message lands only in the authentication instance.
- **F3, Kubernetes and Talos.** Per environment, dev first, then qa, then prod: one lightweight DaemonSet (Fluent Bit or Vector) for container logs with environment, namespace, workload, pod and container labels; a small exporter for Kubernetes Events; Talos service and kernel logs through the machine configuration's own log destinations, no extra agent. Acceptance: logs and Events of a deleted pod are still searchable; a collector restart and a VictoriaLogs restart lose at most the documented buffer.
- **F4, log-derived alerts (D8).** The `vlogs_query` special agent with a short rule set: Proxmox OOM kills with the victim, repeated authentication failures per source, backup job failures. Plus a staleness service per source (no logs from a source for longer than expected is WARN). Acceptance: each rule fired once by a known safe test event and delivered by mail.
- **F5, daily digest.** A daily LogsQL query grouping messages by normalised pattern (numbers and ids collapsed) per source, showing counts, first and last seen and one example, mailed once a day; patterns known to be harmless are suppressed by a short, version-controlled list. It replaces logcheck, whose reports already outgrew the mail relay ([#1961](https://github.com/isejalabs/homelab/issues/1961)). Acceptance: one week of digests reviewed by the owner.
- **F6, remaining sources.** OPNsense `gw2`/`gw3`/`gw4`, Proxmox kernel and OOM, Linux and UCS authentication, TrueNAS apps (RustFS, borgbackup server, syncthing) and Cloud Sync/AD failures, Home Assistant authentication; Immich when it is deployed. Each source gets an owner, a configuration location, a retention class and one example query in a reference doc.
- **F7, budget check.** One measurement after F3 in prod against D7, including collectors and VictoriaLogs housekeeping.

### G — Checkmk configuration record

Tracked in [#2161](https://github.com/isejalabs/homelab/issues/2161).

- [ ] Nightly read-only export of an allow-list of folders, rule sets, notification rules and host attributes of each running site into Git (D9), so the reference docs link to the export instead of repeating rule ids. Fails closed on credentials: secret-bearing values replaced by placeholders, an unknown value aborts the run, a secret scanner before each commit, the first export checked by hand against the secrets in 1Password, and a private repository unless that check shows nothing sensitive is left.
- [ ] The Terraform provider and the two custom special agents re-checked against Checkmk 2.5 (the ADR 0015 spike was on 2.4, and 2.5 changes the password reference format).
- [ ] A short upgrade checklist for the next Checkmk release: what to re-test, in which order.
- [ ] The open post-merge follow-up issues of the Checkmk work reviewed once: closed where done or obsolete, the rest folded into G or E.

### H — Retention and recovery validation

Tracked in [#1442](https://github.com/isejalabs/homelab/issues/1442).

Once F is in prod: retention expiry checked with timestamped test data, a loghost reboot with the expected loss recorded, and one real investigation (an authentication event, an OOM, a deleted pod) done end to end from the workstation. This replaces phase 4 ([#1442](https://github.com/isejalabs/homelab/issues/1442)).

### I — `rebuild_k8s` site for upgrade tests

Tracked in [#2162](https://github.com/isejalabs/homelab/issues/2162).

Purpose (owner, 2026-11-02): before a Kubernetes upgrade, prove on the `rebuild` cluster with the new version that the Checkmk Kubernetes monitoring still works. This reverses the September constraint "no `rebuild_k8s` deployment required".

- [ ] A `rebuild_k8s` Ultimate site in the free licence state on `monitoring1`, configured like `qa_k8s`, without notifications.
- [ ] It runs only while `rebuild` is up (`AUTOSTART` off, started and stopped with the cluster), so it does not cost its share of memory (`dev_k8s` takes about 2.8 GiB) or CPU the rest of the time, and does not report a stopped cluster as down.
- [ ] One upgrade check written down: start the site, upgrade `rebuild`, compare the services with the version before, record the result in the upgrade's issue.

## Order

1. A and B now; A's disk item first, since the forecast date is close.
2. C and D next; D's profile can run during B.
3. E and G alongside, whenever there is time; I before the next Kubernetes upgrade.
4. F after A and B are done, in the order F1 → F2 → F3 (dev, qa, prod) → F4 → F5 → F6, with F7 after F3 in prod.
5. H last.

## Tracking

How the September phase issues map onto this plan, as applied on 2026-11-02. All stream issues are sub-issues of [#71](https://github.com/isejalabs/homelab/issues/71).

| Issue | Change |
| --- | --- |
| [#71](https://github.com/isejalabs/homelab/issues/71) | Umbrella; the body's phase list replaced with streams A to I, outdated constraints dropped ("exclude `core`", "no `rebuild_k8s` deployment required", "authentication: 90 days", "implementation has not started", old placements). |
| [#1437](https://github.com/isejalabs/homelab/issues/1437) phase 0 | Closed: inventory and interfaces done; backup restore moves to A; the NVMe counter repeat belongs to [#1596](https://github.com/isejalabs/homelab/issues/1596); the logging budget is fixed by D7. |
| [#1438](https://github.com/isejalabs/homelab/issues/1438) phase 1A | Rescoped to stream E. |
| [#1439](https://github.com/isejalabs/homelab/issues/1439) phase 1B | Rescoped to F1 to F3 (no Loki pilot, D5). |
| [#1440](https://github.com/isejalabs/homelab/issues/1440) phase 2 | Rescoped to F6. |
| [#1441](https://github.com/isejalabs/homelab/issues/1441) phase 3 | Split: infrastructure notifications moved to [#2158](https://github.com/isejalabs/homelab/issues/2158) (stream B); the issue keeps F4 and F5. |
| [#1442](https://github.com/isejalabs/homelab/issues/1442) phase 4 | Rescoped to H. |
| [#1443](https://github.com/isejalabs/homelab/issues/1443) phase 5 | Closed as done through [#1783](https://github.com/isejalabs/homelab/issues/1783); its archive-restore item is covered by the owner's acceptance of PBS restores (stream A). |
| New | [#2157](https://github.com/isejalabs/homelab/issues/2157) (A), [#2158](https://github.com/isejalabs/homelab/issues/2158) (B), [#2159](https://github.com/isejalabs/homelab/issues/2159) (C), [#2160](https://github.com/isejalabs/homelab/issues/2160) (D), [#2161](https://github.com/isejalabs/homelab/issues/2161) (G), [#2162](https://github.com/isejalabs/homelab/issues/2162) (I). |
| Open post-merge follow-ups of the Checkmk work | Reviewed once as part of [#2161](https://github.com/isejalabs/homelab/issues/2161). |

The two September plans carry a status line pointing to this plan; their bodies stay unchanged.

## Owner's answers (2026-11-02)

- PBS restore: proven with other VMs and LXCs, accepted for the monitoring container too (stream A).
- `rebuild`: `prod` does not need it for Kubernetes monitoring; a `rebuild_k8s` site is needed to test upgrades (D3, stream I).
- Kubernetes in `prod` (2026-11-09): `prod` keeps its Kubernetes special agent and becomes the long-term central site for all hosts and the near-static Kubernetes objects with their trends; the `*_k8s` sites or Prometheus add fine-grained detail (D3). Where Kubernetes objects notify from is open (D2).
- Configuration export (2026-11-09): must not leak credentials kept in Checkmk (D9).
- Service limit of `prod_k8s`: trim Kubernetes services first; Prometheus may take over Kubernetes monitoring if Checkmk becomes the limiting factor (D4).
- Logs: two VictoriaLogs instances, authentication and applications; retention to be decided, authentication likely longer than 90 days (D6, F2).
- Notifications: the mail address stays in a secret, never in a public issue, ADR or plan; push to the phone, since mail is not read often enough, with Pushover preferred over Slack and PagerDuty (2026-11-09) (D11, stream B).
- Load target: try 0.5 cores day average (stream D).

## Still open

1. Retention periods of the two VictoriaLogs instances (decided in F2, before ingest).
2. The push channel: Pushover unless its test in stream B fails, else Slack or PagerDuty.
3. Where Kubernetes objects notify from: the `*_k8s` sites or `prod` (D2, decided in stream B).
4. When Prometheus would replace Checkmk for Kubernetes: what counts as "Checkmk is the limiting factor" (for example, trimming below a minimum useful service set, or the free licence terms changing).
