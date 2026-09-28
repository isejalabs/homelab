# Observability implementation plan

**Date:** 2026-09-28. **Status:** Planning complete; implementation not started. **Assessment:** [September 2026 observability assessment](../audits/2026-09-observability.md). **Tracking:** [O11Y umbrella issue](https://github.com/isejalabs/homelab/issues/71).

This plan preserves Checkmk metrics/history, closes capacity gaps and adds useful log collection and analysis with measured SSD overhead. Backend selection remains a pilot outcome. Recording the plan and issues does not deploy services or authorize unrelated upgrades, quota removal or Checkmk retirement.

## Constraints and operating model

- Keep `core` Smart Ping out of scope. No new `rebuild_k8s` site is required.
- Preserve existing RRDs, graph-rich email and healthchecks.io coverage. An eventually retired Checkmk installation may be retained as a restorable, normally stopped archive.
- Extend loghost outside Kubernetes; brief downtime and buffered-data loss are acceptable. No replicated backend or whole-site monitor is required.
- Prefer €0 recurring costs; consider up to €5/month only for demonstrated value. Measure RAM/CPU and physical host writes, including collection and storage overhead.
- Manage Linux services through Salt and Kubernetes collectors through this repository's Flux conventions. Record manual Checkmk and TrueNAS settings, because they are currently configured through their UIs. TrueNAS has SSH but no Salt.
- Require remote CLI log querying without logging into loghost. Evaluate native `logcli` usability against a documented VictoriaLogs query workflow.
- Follow repository branch, PR and non-prod testing conventions for each implementation. Do not fill production disks or induce OOM on production hosts to test notifications.

## Phase 0 — Baseline, inventory and preservation

Read live configuration without changing it. Confirm site placement (including the initially reported `prod_k8s`), RRD archive definitions, capacity rules, notifications, host/loghost configuration, collector reachability and backup/restore arrangements. Inventory CPU, memory, temperature and capacity graphs that must remain available.

Measure representative host-write deltas and workload/log volume for approximately seven days, including backup-heavy periods. Record SMART/NVMe host writes, block-device/LXC attribution where available, host workload changes, backend filesystem growth and CPU/RAM. Do not infer physical NAND writes from host writes if the device does not expose them. Establish an agreed incremental GB/day and RAM budget from this baseline rather than inventing one.

Acceptance:

- [ ] Current site/source inventory and actual RRD resolutions/retention recorded.
- [ ] Checkmk backups shown to be recoverable, including old graphs in an isolated restore where feasible.
- [ ] Loghost traffic and SSD write/resource baseline recorded with units, intervals and known confounders.
- [ ] Relevant RustFS, Longhorn and Talos collection interfaces inspected without changing workloads.
- [ ] Pilot resource/write budget recorded before judging candidate results.

## Phase 1A — Missing capacity checks

Add Checkmk services for Longhorn backing disks and RustFS buckets. The additional Talos disks are exclusively Longhorn disks, so do not duplicate checks under a separate project. Preserve ZFS dataset/pool and PVC filesystem checks.

For Longhorn, collect per-node/per-disk total, actual used/free capacity, scheduling headroom and health. Keep allocated/scheduled bytes distinct from actual physical use. Use stable identities and least-privilege access. For RustFS 1.0.0-beta.12, validate the exact accounting interface and collect logical bytes, quota, headroom and data age. Prefer existing server-side accounting over repeated full listings; measure any listing fallback before adopting it. Retain quotas initially.

Start evaluation at one-minute disk polling and 15-minute bucket polling, adapting to accounting freshness/cost. Thresholds must cover percentage and absolute reserve, plus growth where meaningful. Allow for backup staging and replica recovery space. Reuse established Checkmk filesystem trend behavior where supported; a generic graphable local-check metric alone is not sufficient. Record the forecasting window, minimum sample history, behavior for flat/negative growth and bursty backup retention cycles.

Acceptance:

- [ ] Values reconciled against Longhorn/TrueNAS/RustFS views and representative known data.
- [ ] Stable services and useful RRD graphs exist for active storage sources.
- [ ] WARN/CRIT, stale/missing data and recovery behavior tested using fixtures or non-prod resources.
- [ ] Time-to-full/quota demonstrated where reliable; insufficient history and unknown growth are explicit.
- [ ] Bucket and physical-capacity checks remain distinct; no quota removed as part of this phase.
- [ ] Salt changes and manual Checkmk settings documented with rollback instructions.

Depends on phase 0's inventory and collection feasibility; capacity work need not wait for logging selection.

## Phase 1B — Searchable logging and remote CLI pilot

Pilot on loghost with one non-prod environment, initially `dev`, while preserving current syslog collection. Compare syslog-ng/compressed files as a baseline, single-node VictoriaLogs and single-binary Loki. Run candidate measurements sequentially or otherwise control for duplicate ingestion so extra writes are attributable. Do not deploy complete stacks in every environment.

Collect node container logs and Kubernetes Events separately. Preserve timestamps, environment, namespace, workload and pod/container identity. Validate Talos access and Event watcher permissions. Use bounded queues/batches; document what is lost during prolonged outages and how recovery works. Protect query access and credentials; remote convenience must not expose the log store publicly.

Exercise from the workstation: search a time range; filter host/environment/namespace/workload; search an authentication failure; retrieve JSON; follow new entries; query a deleted pod. Native `logcli` is an advantage for Loki. A lightweight maintained client/API workflow can qualify for VictoriaLogs, but a substantial custom CLI is a maintenance cost, not a free feature.

Acceptance:

- [ ] Events and selected pod logs remain searchable after the pod disappears.
- [ ] Remote query scenarios work without SSH to loghost, with documented authentication and bounded result sizes.
- [ ] Candidate retention/routing supports 90-day authentication history and shorter application history, potentially using a separate compressed archive.
- [ ] Measured added host writes, RAM/CPU, ingest rate and query latency include rotation/compaction periods and collector overhead.
- [ ] Backend outage/restart, bounded buffering, collector restart and stale-collection detection tested.
- [ ] Candidate selected using weights: capacity/alerts 25%, SSD/resources 25%, maintenance 25%, history/analysis 20%, resilience 5%; record evidence and rejection reasons.
- [ ] Salt/GitOps configuration, manual steps and rollback documented; temporary test resources cleaned up.

Depends on phase 0. Can proceed alongside phase 1A. There is no commitment to VictoriaLogs or Loki before the pilot.

## Phase 2 — Required source coverage

Roll out the chosen collection path to prod and appropriate active environments. Respect dormant environments and retain the shared backend. Verify each source with a known safe event rather than assuming system syslog contains every application event.

Acceptance:

- [ ] Kubernetes container logs and Events, including workload identity, collected from intended environments.
- [ ] Proxmox kernel/OOM and Linux/UCS authentication/application logs verified.
- [ ] TrueNAS 25.10 container logs (RustFS, borgbackup server, syncthing) and Cloud Sync/AD synchronization failures verified through supported collection routes.
- [ ] OPNsense gw2/gw3/gw4 logs verified.
- [ ] Home Assistant authentication events verified; Immich collection documented as an onboarding item until deployed.
- [ ] Backup coverage matrix distinguishes healthchecks.io-monitored jobs, kopiur backup freshness and failure-detail logs.
- [ ] Every source has an owner/configuration location, retention class, example query and collection-health signal.

Depends on phase 1B. Future Immich deployment is an explicit deferred source, not a reason to leave all current source coverage unfinished.

## Phase 3 — Alerts and daily digest

Keep email as the primary existing notification channel; optionally add Slack webhooks for selected critical events within the free workspace's integration limit. Keep notification ownership explicit to avoid duplicate alerts between Checkmk, log rules and healthchecks.io.

Acceptance:

- [ ] Disk/quota CRIT notifies promptly; ordinary unavailable services notify after ten continuous minutes with recovery handling.
- [ ] Proxmox OOM alerts contain available victim/process/container context.
- [ ] Authentication rules detect useful patterns such as repeated failures without paging on every ordinary failure.
- [ ] Backup failures and overdue success are covered; existing healthchecks.io checks remain effective.
- [ ] Daily digest groups unfamiliar patterns with counts, first/last occurrence and examples/query links.
- [ ] Suppressions are narrow, version-controlled where possible and reviewable; old logcheck rules are not copied wholesale.
- [ ] Known safe test events exercise detection, routing, deduplication, recovery and notification delivery.
- [ ] Missing/stale collection has an explicit signal.

Depends on phase 1A and phase 2 for full rollout. Rule design and pilot-source experiments can start during phase 1B.

## Phase 4 — Retention, write budget and recovery validation

Initial policy: preserve verified Checkmk tiered RRD history; authentication 90 days; Kubernetes Events seven days; application logs three to seven days. Keep current compressed system-log retention initially. Explicit pattern detection does not eliminate the need to investigate unknown failures later.

Acceptance:

- [ ] Retention expiry verified with timestamped test data; archive and searchable-store coverage clearly distinguished.
- [ ] Logging-disk pressure and queue limits handled without unbounded growth or silent premature loss of required history.
- [ ] Loghost reboot/backend restart and a simulated collector interruption tested; expected losses recorded.
- [ ] Representative investigation retrieves a historical authentication event, OOM context and deleted-pod evidence remotely.
- [ ] Sustained incremental host writes and resources meet the phase-0 budget; resource costs include all collectors and backend housekeeping.
- [ ] Restore/recovery and operating instructions recorded, including manual TrueNAS/Checkmk steps.

Depends on phase 3. Earlier phases should test their own behavior; this phase validates the integrated result.

## Phase 5 — Optional consolidation and historical archive

Review whether consolidating `free`/`prod` or other duplicated configuration actually reduces maintenance. No replacement of Checkmk is required. Exclude `core`. Do not retire a working site solely because the pilot succeeds.

Acceptance:

- [ ] Record consolidate/retain decision and maintenance benefit; a justified no-change decision can complete the evaluation.
- [ ] If retiring a site, preserve a consistent installation/configuration/RRD backup and document compatible restore requirements.
- [ ] Restore the archive in isolation and open representative old graphs before retirement.
- [ ] Preserve host/service identity or document discontinuities; ensure no monitoring/notification gaps.

Depends on phase 4 for any retirement decision. Actual consolidation is optional.

## Implementation prerequisites

Before production rollout of a component, its non-prod acceptance checks and rollback method must be recorded and confirmed under the repository's prerequisite-confirmation convention. Before removing any check or retiring a Checkmk site, replacement coverage and historical restore must be explicitly confirmed. These are future implementation gates, not prerequisites to saving this plan or creating tracking issues.

## Tracking

All phases are native sub-issues of [#71](https://github.com/isejalabs/homelab/issues/71), with blocked-by relationships reflecting the dependencies above. These are planned work, not post-merge follow-ups.

- [ ] Observability phase 0 — Baseline, inventory and preservation (see [#1437](https://github.com/isejalabs/homelab/issues/1437))
- [ ] Observability phase 1A — Missing capacity checks (see [#1438](https://github.com/isejalabs/homelab/issues/1438))
- [ ] Observability phase 1B — Searchable logging and remote CLI pilot (see [#1439](https://github.com/isejalabs/homelab/issues/1439))
- [ ] Observability phase 2 — Required source coverage (see [#1440](https://github.com/isejalabs/homelab/issues/1440))
- [ ] Observability phase 3 — Alerts and daily digest (see [#1441](https://github.com/isejalabs/homelab/issues/1441))
- [ ] Observability phase 4 — Retention, write budget and recovery validation (see [#1442](https://github.com/isejalabs/homelab/issues/1442))
- [ ] Observability phase 5 — Optional consolidation and historical archive (see [#1443](https://github.com/isejalabs/homelab/issues/1443))
