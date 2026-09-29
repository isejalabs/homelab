# Observability implementation plan — independent pass

**Date:** 2026-09-29. **Status:** Independent second plan, produced for comparison; not a replacement. **Assessment:** [independent-pass assessment](../audits/2026-09-observability-claude.md). This plan and its companion assessment were produced from scratch, without reading the already-merged [`2026-09-observability.md`](../audits/2026-09-observability.md) assessment or its [companion plan](2026-09-observability.md), at the owner's request to compare two independent analyses of the same brief. No tracking issue or sub-issues have been created for this pass — it exists as a documentation artifact for comparison only, per the owner's instruction for this exercise.

This plan closes the Longhorn/RustFS capacity gaps, brings loghost's own configuration under version control, and adds searchable logging and remaining source coverage, all measured against a write-endurance budget on the always-on system SSDs rather than against polling frequency alone.

## Constraints and operating model

- Preserve Checkmk's existing RRD history, graph-rich email alerting, and healthchecks.io coverage; nothing here requires retiring or replacing Checkmk.
- Distinguish the two SSD-related constraints explicitly: USB-attached backup-disk spin-up avoidance (already satisfied by the existing daily SMART/usage cadence) versus always-on system-SSD write endurance (governed by bytes written per day, independent of poll frequency) — see the companion assessment's clarified model.
- Recurring cost ceiling is approximately €5/month, spent only where clearly justified; €0 remains preferred by default.
- Manage Linux-side changes (loghost's syslog-ng/logcheck configuration, any new log-shipping agent) through Salt in `sebiklamar/salt-iseja.net`; manage Kubernetes-side changes (log/event collectors, Checkmk local checks delivered as manifests) through this repository's Flux conventions. Document any Checkmk or TrueNAS/RustFS UI configuration that remains manual, since neither is managed as code today.
- Prefer the resource/write-footprint-lightest option at each decision point, per the owner's own stated top priority; verify that preference with measurement rather than assumption before committing to a backend.
- Satisfy outage-resilience by extending the existing external-heartbeat pattern already used for backup monitoring, not by introducing a new cloud service, unless a pilot shows that approach insufficient.
- Follow each repository's own branch, PR, and non-production testing conventions when this plan moves into implementation; do not test capacity-exhaustion or OOM alerting against production hosts.

## Phase 0 — Baseline and live verification

Read live configuration without changing it, since this plan was built entirely from repository evidence and cannot see current runtime state. Confirm actual Checkmk site inventory and RRD retention settings, including whether the reported `dev_k8s` site is still active given that `dev` only receives Kubernetes' minimal Flux app set and therefore has no Checkmk agent deployed to it via GitOps today. Locate where the `roles:loghost` grain is actually set, since it does not appear anywhere in the `salt-iseja.net` repository. Measure actual persistent journald retention on a representative host, since the tracked configuration leaves `SystemMaxUse` unset. Establish a measured baseline of host-write deltas on the always-on system SSDs (not just the USB backup disks) over a representative period, including backup-heavy windows, to turn the write-endurance constraint into a concrete per-candidate budget rather than a qualitative preference.

Acceptance:

- [ ] Live Checkmk site/RRD inventory recorded, including the `dev_k8s` discrepancy resolved one way or the other.
- [ ] `roles:loghost` grain source located and documented.
- [ ] Persistent journald retention measured on a representative host.
- [ ] Always-on system-SSD host-write baseline recorded in bytes/day, with backup-window periods called out separately.
- [ ] RustFS and TrueNAS collection interfaces inspected against the versions actually deployed, without changing any workload.

## Phase 1 — Close the ungated capacity gaps

Add Checkmk services for Longhorn per-node/per-disk usage, free space, scheduling headroom and health, and for RustFS bucket logical usage, quota headroom and data freshness. Treat this as higher priority than any logging work, because Longhorn's default `StorageClass` currently reserves zero headroom on its disk (`storageReservedPercentageForDefaultDisk: 0`) and nothing scrapes any capacity metric for either source today — a full disk fails hard, not gracefully, in the current state. Reconcile any new check's reported numbers against the Longhorn UI's and RustFS's own reporting before trusting them for alerting. Preserve the existing daily USB backup-disk SMART/usage cadence unchanged; new checks must not introduce additional spin-ups for that class of disk.

Acceptance:

- [ ] Longhorn disk usage/headroom/health and RustFS bucket usage/quota/freshness visible as Checkmk services with working WARN/CRIT thresholds.
- [ ] Values reconciled against Longhorn's and RustFS's own reporting on at least one non-production environment.
- [ ] No additional USB backup-disk spin-ups introduced.
- [ ] Time-to-full forecasting demonstrated where Checkmk's trend behavior supports it for the new check types; explicitly noted where it does not.

Depends on phase 0's inventory; does not depend on any logging-related phase.

## Phase 2 — Version-control loghost's own configuration

Bring the currently unmanaged syslog-ng receiver configuration and a freshly authored logcheck-equivalent ruleset (or its replacement, see phase 3) into Salt, replacing the bare `pkg.installed` state that exists today. Assign the `roles:loghost` grain through a tracked mechanism rather than leaving host-to-role assignment invisible to the repository. This phase stands on its own regardless of which logging backend, if any, is chosen next — even keeping flat compressed files as the long-term approach still benefits from this.

Acceptance:

- [ ] syslog-ng receiver configuration exists as a Salt state, not a manual on-box edit.
- [ ] `roles:loghost` grain assignment is version-controlled or its external source is documented if it must remain outside the repository.
- [ ] A minimal, reviewable allow-list/digest rule set replaces the old logcheck rules, authored fresh rather than copied wholesale.

Depends on phase 0 locating the current grain source; independent of phase 1.

## Phase 3 — Searchable-logging pilot, measured against the write-endurance budget

Pilot a single-node VictoriaLogs deployment on loghost against one non-production environment, alongside the flat-file-plus-digest baseline from phase 2, and measure actual host-write bytes/day for each against the phase-0 baseline before choosing. Prefer VictoriaLogs' generally lighter steady-state footprint over Loki's filesystem-storage mode at this scale, per the owner's stated top priority, but confirm that with the measurement rather than deciding from general reputation alone. Collect Kubernetes container logs and Kubernetes Events separately from the metrics path (no such collection exists in-cluster today), preserving timestamps, environment, namespace, workload, and pod/container identity.

Acceptance:

- [ ] Candidate backend selected using the weighted comparison in the companion assessment (SSD/resource footprint 35%, maintenance 25%, capacity/alerts 20%, history/analysis 15%, resilience 5%), with measured evidence recorded, not estimated.
- [ ] Kubernetes Events and pod logs remain queryable after the originating pod is deleted, within the chosen retention window.
- [ ] Measured host-write bytes/day for the chosen backend, including index/compaction overhead, stays within the phase-0 budget.
- [ ] Backend restart/outage behavior and bounded buffering tested; expected data loss during an outage is documented.

Depends on phase 0's write-endurance baseline and phase 2's version-controlled receiver configuration.

## Phase 4 — Remaining source coverage

Roll out the chosen collection path to the active environments and remaining sources: TrueNAS container logs (RustFS, borgbackup server, syncthing) and service failures (Cloud Sync, AD directory sync), OPNsense gw2–gw4, Linux/UCS authentication and application logs, and authentication events from Home Assistant now and Immich once deployed. Verify each source with a known, safe test event rather than assuming system syslog already carries every application-level event.

Acceptance:

- [ ] Each source has a documented owner, configuration location, retention class, example query, and a signal for when its own collection goes stale or stops.
- [ ] Authentication sources retain 90 days, per the owner's stated target.
- [ ] Backup-related logging is explicitly distinguished from healthchecks.io's own job-success monitoring, so the two don't produce duplicate or conflicting signals.

Depends on phase 3's backend selection.

## Phase 5 — Alerting and outage-resilience heartbeat

Keep Checkmk email as the primary notification channel. Add a periodic dead-man's-switch check-in from Checkmk or loghost to the existing healthchecks.io service (already used for backup-job monitoring, and already patterned by `zrepl-healthcheck-hook.sh`), so a missed check-in — host down, power loss, or network loss — produces a notification reachable independent of home-network state, without introducing a new cloud dependency or measurable new write load. Build the daily unfamiliar-pattern digest on top of the backend chosen in phase 3, grouped by source/service with counts and first/last occurrence.

Acceptance:

- [ ] A missed heartbeat check-in is demonstrated to produce a visible alert during a simulated outage test on a non-production host.
- [ ] Disk/quota CRIT and Proxmox OOM events notify promptly; ordinary service unavailability follows the existing delay policy.
- [ ] Daily digest running and reviewed for at least one full week before being considered complete.

Depends on phase 4 for full source coverage feeding the digest; the heartbeat itself can be implemented as soon as phase 0 confirms loghost's identity.

## Phase 6 — Retention and recovery validation

Confirm the 90-day authentication retention, the preserved roughly 700-day Checkmk RRD history, and the actual persistent journald retention measured in phase 0 all hold under real operation, including through a loghost reboot and a simulated backend restart. Validate that a representative historical investigation — an authentication event, an OOM's victim context, evidence from an already-deleted pod — can actually be retrieved through the new tooling before calling this plan complete.

Acceptance:

- [ ] Retention windows verified with timestamped test data for each source class.
- [ ] Loghost reboot and backend-restart data-loss behavior tested and documented as acceptable or not.
- [ ] At least one representative historical investigation completed end-to-end using only the new tooling, without SSH-and-grep.

Depends on phases 1 through 5.

## Relationship to the already-merged plan

This plan was built independently and does not assume or require the already-merged [`2026-09-observability.md`](2026-09-observability.md) plan's phase numbering, tracking issue, or sub-issues. Reconciling the two into a single execution plan, if desired, is a separate step the owner can take after comparing them — this document does not attempt that reconciliation itself.
