# Observability assessment — September 2026

**Date:** 2026-09-28. **Reviewed:** 2026-09-29. **Status:** Assessment complete for planning; live configuration and performance validation pending. **Scope:** Homelab metrics, capacity, logs, alerting, history and operating cost.

This is a point-in-time assessment based on the owner's inventory and requirements, repository inspection and upstream documentation. It does not claim that live systems have been audited. The [implementation plan](../plans/2026-09-observability.md) records phases and acceptance criteria. Implementation has not started.

## Decision summary

Keep Checkmk as the infrastructure metrics, capacity-alerting and historical-graph system. Close Longhorn disk and RustFS bucket coverage gaps while piloting Kubernetes logs and Events. Extend the existing external loghost, with remote command-line querying as a required capability. Do not require a new physical host, paid monitoring edition, cloud service, replicated logging deployment or replacement metrics stack.

Preserve existing RRD history. A retired Checkmk installation may be kept as a restorable, normally stopped archive; exporting graphs or migrating every historical sample is not required. No retirement is currently planned.

## Evidence and current state

### Monitoring and access

| Component | Reported state |
| --- | --- |
| `monitoring1.home.iseja.net` | LXC on pve6; sites include `dev_k8s` and `qa_k8s` on 2.4.0p36.cce |
| `monitoring2.home.iseja.net` | LXC on pve4; `prod` and historical sibling `free`, both 2.4.0p36.cre |
| `core` on monitoring1 | 2.5.0p12.ultimate for one-second Smart Ping of physical/network hosts; explicitly outside this project |
| `prod_k8s` | Reported in the initial inventory, but absent from supplied `omd sites` output; placement/current status remains to verify |
| `rebuild_k8s` | Not currently in scope; initially mentioned accidentally; a copied site could later support upgrade testing |
| `loghost.home.iseja.net` | LXC on pve1; syslog-ng and logcheck; Linux system logs forwarded centrally |
| LXC storage | Local ZFS volumes on each Proxmox host's single disk |
| Configuration | Salt manages Linux host configuration, including monitoring1/2 and loghost; Checkmk application configuration and TrueNAS/container management are manual UI operations |
| Access | SSH available to all hosts; regular Salt management on Linux; limited historical `salt-ssh` use for the `apps/check-mk/client` formula on TrueNAS, not general TrueNAS management |
| Log investigations | Currently SSH plus listing/grepping on loghost; remote querying comparable to `logcli` is desired |

Checkmk already provides useful Linux filesystem monitoring, PVC usage via workloads, ZFS monitoring and compact historical RRD graphs. The owner estimates approximately 700 days of history with progressively coarser resolution; actual archive settings remain unverified. Community-site dynamic Kubernetes host management is limited, with manually maintained stable workload objects used as a workaround. Commercial-edition Kubernetes sites use the available free allowance; entitlement and upgrade compatibility must be verified before relying on new edition features.

The repository contains [Checkmk collector configuration](../../k8s/apps/monitoring/checkmk-agent/base/helmrelease.yaml), [Longhorn configuration](../../k8s/infra/longhorn-system/longhorn-core/base/helmrelease.yaml), and Grafana/Prometheus chart-source and bootstrap CRD entries. The latter do not demonstrate a running metrics backend. Salt configuration inspected in the sibling `salt-iseja.net` repository declares syslog-ng/logcheck on loghost and TCP syslog forwarding from Linux clients. Neither repository proves the exact live configuration.

The current standard Checkmk polling interval is five minutes for services generally. USB-powered backup disks have daily SMART checks and daily storage-usage updates to allow them to sleep for most of the day. The owner reports that usage retrieval does not wake them, apparently using ZFS-cached information; the exact mechanism remains to verify. Preserve this behavior when collecting baseline data or adding checks.

### Workloads and storage

Prod has three control-plane and three worker nodes, approximately 100 pods, and is still being built out before additional applications such as Immich. See [environments](../architecture/environments.md). Other environments have different availability and backup schedules; intentionally inactive environments must not generate routine outage alerts.

At assessment time, TrueNAS runs version 25.10 and RustFS runs 1.0.0-beta.12. These are inventory observations, not fixed design constraints: both may be upgraded separately from this plan. Before selecting collection interfaces, check newer releases for useful features and compatibility, then validate against the actual deployment version. Any required upgrade belongs in separately tracked work. RustFS has eight environment-specific kopiur backup buckets, four actively used, quotas enabled and no object versioning. Existing Checkmk monitoring covers physical usage of `natascha1/gamma/srv/rustfs`. See [storage architecture](../architecture/storage.md) and [kopiur backup/restore](../kopiur-backup-restore.md).

The additional Talos data disks are used solely by Longhorn: these are one coverage gap, not separate filesystem projects. Shared Terragrunt disk tiers are 10/20/30 GB, with prod selecting the largest. Longhorn uses `/var/mnt/longhorn`; physical usage, scheduling headroom and PVC filesystem fullness are different measurements.

| Capacity layer | Existing coverage / required addition |
| --- | --- |
| Linux filesystems and TrueNAS ZFS | Preserve working Checkmk checks and trends |
| PVC filesystems | Preserve existing coverage; verify completeness as workloads grow |
| Longhorn backing disks | Add actual usage/free space, scheduling headroom, disk health and growth |
| RustFS buckets | Add logical bytes, quota/headroom, growth and freshness |
| RustFS physical storage | Preserve existing ZFS dataset/pool checks |

Longhorn source-disk usage cannot substitute for RustFS backup-bucket monitoring. Retention, deduplication and deletions cause backup growth to differ from source growth. Quotas are protective limits, whereas monitoring reports risk; retain quotas initially and review them only after usage and backup-success monitoring are reliable.

### Resource and durability constraints

The owner reports approximately 25 GB free RAM across hosts, shared with future services. Reported 15-minute loads are 3, 9 and 5 on Intel i5-1145G7 systems; load alone does not establish CPU saturation or available capacity. Reported `tank` free space is 322 GB on pve6, 281 GB on pve1 and 288 GB on pve4. Capacity is currently less concerning than write endurance.

One 512 GB SSD wore out after approximately three years and 138 TB written. The pve1 SSD reports 203 TB written and 91% endurance used. These are owner-reported observations, not a confirmed explanation of workload attribution or an exact failure forecast. Repeated test-VM creation is a hypothesis for additional wear, not a measured cause.

One year of compressed syslog archives occupies approximately 760 MB. Example daily counts are 320,000 lines recently and 133,000 on an older sampled day. These samples indicate a need to measure current traffic, not a reliable growth forecast. Compressed retained bytes do not measure SSD writes: ingestion, indexes, compaction, journals, ZFS, snapshots and replication all matter.

The preferred recurring cost is €0; up to €5/month is acceptable when justified. Brief loghost downtime during host reboot and loss of buffered logs are acceptable. Whole-site outage detection is unnecessary. Existing off-host syslog collection is useful separation; journald's reported 10 MB cap guarantees no particular historical duration. No HA logging requirement remains.

## Requirements and assessment

| Requirement | Assessment / target |
| --- | --- |
| WARN/CRIT and time-to-full | Preserve Checkmk behavior and extend it to missing capacity sources; test forecasting explicitly |
| Linux log collection | Retain syslog-ng forwarding and efficient compressed archive |
| Kubernetes logs and Events | Missing; collect separately, with cluster/workload identity and timestamps |
| Low SSD writes | Primary design constraint; measure incremental host writes, not only storage consumption |
| Availability during reboot | Optional; temporary gaps and buffered loss accepted |
| Log analysis | Explicit actionable rules plus grouped daily unfamiliar-message digest |
| Alerting | Keep graph-rich email; disk CRIT promptly, service unavailability after ten continuous minutes; optional Slack |
| Long history | Retain approximately 700-day tiered RRD history after verifying settings; CPU, memory, temperature and capacity correlations matter |
| Authentication history | 90 days for operational audit/investigation; no tamper-evident/compliance requirement was requested |
| Application history | Start at 3–7 days; Kubernetes Events at 7 days, subject to pilot evidence |
| Remote log access | Query from the workstation without SSH/grep; time/source filters, search, streaming/tail, structured output and bounded queries |
| Administration | Salt-managed Linux services and GitOps Kubernetes collectors; document manual Checkmk and TrueNAS changes |

Source rollout must include Proxmox kernel/OOM logs, Linux/UCS application and authentication logs, TrueNAS RustFS/borgbackup/syncthing logs, Cloud Sync and AD synchronization failures, OPNsense gw2/gw3/gw4, Home Assistant authentication and future Immich. Keep existing healthchecks.io backup checks; add details and missing-success coverage where absent. Windows, switch/AP logging, distributed tracing and whole-site detection are non-goals for this rollout.

## Architecture and candidate assessment

Use Checkmk for stable infrastructure measurements and notification ownership. A lightweight Longhorn/RustFS integration is preferable to installing a complete metrics stack solely for these gaps. Local checks can supply metrics and states, but graphing a metric does not automatically grant Checkmk filesystem forecasting; compatibility with trend helpers and the installed editions must be proven.

Keep log persistence on loghost outside the monitored Kubernetes clusters. Use node collectors for container logs and an Event watcher for Kubernetes Events. Keep source/environment labels and collector freshness visible. Avoid deploying a duplicate full logging stack per environment. Salt and GitOps remain the relevant configuration mechanisms; manual application changes need recorded settings and recovery instructions.

| Candidate | Strength | Main unresolved cost or limitation | Position |
| --- | --- | --- | --- |
| syslog-ng + compressed files | Existing efficient archive, few new components | Remote structured querying and digest/rule maintenance | Baseline and fallback; needs a safe remote query interface to meet the access requirement |
| Single-node VictoriaLogs on loghost | Searchable store, HTTP querying and Kubernetes collection options | Measure writes; validate remote CLI workflow and differentiated retention | First pilot candidate, provisional |
| Single-binary Loki on loghost | Grafana ecosystem and native `logcli` workflow | Measure indexing/chunk/WAL/retention overhead and operational effort | Close alternative, stronger fit for native CLI preference |
| Replicated in-cluster logging | Storage availability | More replicated writes and cluster dependencies than required | Defer |

An API used through a maintained CLI or small documented client may satisfy the remote-access requirement; do not assume a bespoke substantial query tool is acceptable. Compare Loki's native `logcli` with the VictoriaLogs workflow during the pilot. This newly clarified requirement can change the candidate ordering.

Weights: capacity and alerts 25%, SSD/resources 25%, maintenance 25%, history/analysis 20%, resilience 5%. Budget, historical preservation and required query/retention behavior are constraints. Numerical candidate scores remain pending evidence; there is no measured efficiency winner yet.

Grafana is a query/visualization layer, not the owner of retention. Tiered historical resolution is possible with an appropriate backend, but adding one is unnecessary while RRDs meet the requirement. Cloud services are optional, not an architectural dependency. Slack webhooks are a possible free notification supplement, subject to workspace integration limits.

## Analysis and alert policy

Start with a small, explicit rule set: Proxmox OOM kills with victim context; repeated authentication failures and relevant administrative events; backup failures and overdue successful backups. Preserve healthchecks.io ownership where already established rather than issuing duplicate alerts. Ordinary service outages notify after ten minutes; capacity exhaustion and OOM events should not inherit that blanket delay.

The daily digest groups normalized message patterns by source/service, shows counts and first/last occurrence, and includes representative examples or query links. Use narrow, reviewable suppressions rather than copying the entire old logcheck rule set. Track collection failures so absence of logs cannot silently imply health. Known-pattern detection complements retained evidence; it cannot anticipate every future investigation.

## Validation still required

- Live RRD retention, capacity rules, site inventory (including `prod_k8s`) and recoverable Checkmk backups.
- RustFS bucket accounting/quota interfaces, permissions, freshness and cost for the deployed and candidate upgrade versions. Check newer features and compatibility before choosing an integration; do not constrain the design to beta.12 or assume current documentation describes it.
- A beta.12 upstream report describes quota-enabled writes failing when accounting was unavailable; verify applicability to the version in use, including any newer fix, rather than assuming the installation is affected or removing quotas preemptively.
- Longhorn per-node values, scheduling settings, stable service naming and Checkmk forecasting integration.
- Current log volume by source, baseline SSD host-write deltas and collector/backend overhead during backup/rotation/compaction periods.
- Talos collector mounts/permissions, log extraction routes for the deployed/candidate TrueNAS versions and supported application authentication events. Preserve daily USB backup-disk checks without additional spin-ups.
- Backend-specific differential retention, remote CLI usability, notification routing and bounded buffering.

## References

- [Kubernetes logging architecture](https://kubernetes.io/docs/concepts/cluster-administration/logging/): container logs are node-side data, not an etcd log archive.
- [Kubernetes API server flags](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/): Events default to one-hour retention; surviving conditions and logs sometimes explain older incidents but are not a guaranteed archive.
- [Checkmk local checks](https://docs.checkmk.com/latest/en/localchecks.html).
- [Checkmk 2.5 release notes](https://checkmk.com/product/release-notes/2-5-0): edition changes and OpenTelemetry availability require care before upgrading free-use sites.
- [Longhorn disk management](https://longhorn.io/docs/1.12.1/nodes-and-volumes/nodes/multidisk/) and [settings](https://longhorn.io/docs/1.12.1/references/settings/).
- [RustFS current observability documentation](https://docs.rustfs.com/en/operations/observability) and [rustfs/rustfs#5716](https://redirect.github.com/rustfs/rustfs/issues/5716): the latter is a reported beta.12 incident, not a diagnosis of this homelab.
- [VictoriaLogs](https://docs.victoriametrics.com/victorialogs/) and [query API](https://docs.victoriametrics.com/victorialogs/querying/).
- [Loki filesystem storage](https://grafana.com/docs/loki/latest/operations/storage/filesystem/) and [LogCLI](https://grafana.com/docs/loki/latest/query/logcli/).
- [Grafana data sources](https://grafana.com/docs/grafana/latest/datasources/) and [Thanos compaction/retention](https://thanos.io/tip/components/compact.md/).
- [Slack free-plan limitations](https://slack.com/intl/en-gb/help/articles/27204752526611-Feature-limitations-on-the-free-version-of-Slack) and [incoming webhooks](https://docs.slack.dev/reference/scopes/incoming-webhook/).
