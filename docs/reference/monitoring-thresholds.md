---
status: current
---

# Monitoring thresholds

**Status:** current as of 2026-10-25. Read from the live `prod` Checkmk site (`monitoring2`) over read-only SSH and the Proxmox hosts (`qm config`, `pve4`/`pve5`) on that date; the rules below were created or changed through the Checkmk REST API with the `terraform` automation user. They are click-ops-style rules without Terraform code (the provider has no module for these rulesets, see [ADR 0015](../decisions/0015-checkmk-configuration-as-code.md)), so this page is the written record: if it and the live site disagree, the site wins and this page is stale.

**Tracking:** [#1847](https://github.com/isejalabs/homelab/issues/1847), umbrella [#71](https://github.com/isejalabs/homelab/issues/71). Site inventory: [`monitoring-sites.md`](monitoring-sites.md); notification settings: [`monitoring-notifications.md`](monitoring-notifications.md).

Thresholds that were tuned because the alert did not match a real fault, the reasoning behind them, and what is deliberately left alone.

## Rules in place

| Ruleset | Folder | Value | Rule id | Why |
| --- | --- | --- | --- | --- |
| Proxmox VE memory percentage used | `k8s/nodes` | fixed 105 / 110 % | `2b4d9ec9-7ece-4846-a317-545d9bc19ef0` | [Measurement artifact](#proxmox-vm-memory-above-100) |
| File systems (used space and growth) | `/` (all hosts except `pve5`), rule `e6eee1a8-0ba3-427f-ba66-6527d3d9430a` | `magic` 0.95, `magic_normsize` 1 GiB (was 0.9 and the default 20 GiB), trend unchanged | (edited) | [Size-scaled levels](#filesystem-levels) |
| File systems (used space and growth) | `k8s/nodes`, item `^/$` | `levels` 86 / 91 %, `magic` 1.0 | `633b494a-871d-4289-8378-41115c527feb` | [Kubelet garbage collection](#kubernetes-node-root-filesystem) |
| Memory and swap usage on Linux | `k8s/nodes` | `levels_committed` ignore | `e8ac31fb-7bba-49aa-b5af-dbb269be1ee7` | Existing since 2026-10-17, see [below](#committed-memory) |

For a rule of this ruleset the "Services" condition matches the **item** (`/`), not the service description (`Filesystem /`): the first version of the node rule used `^Filesystem /$` and silently matched nothing.

## Proxmox VM memory above 100 %

`Proxmox VE Memory Usage` showed 101 – 102 % (for example 6.08 of 6.00 GiB) on the Talos VMs. Cause: the VMs have **`balloon: 0`** (checked with `qm config` on `pve4`/`pve5`; `agent: enabled=1` is set, but the guest agent does not feed this value). Without a balloon device Proxmox cannot look into the guest and reports the resident set size (RSS) of the VM's `kvm` process, which includes the guest's page cache and about 50 – 90 MB of QEMU overhead. A guest that has touched all of its RAM therefore reads about 101 %, independent of real pressure.

| VM | Proxmox `mem` / `maxmem` | Guest `Memory` check |
| --- | --- | --- |
| `qa-ctrl-02` | 101.2 % | 72.5 % |
| `prod-ctrl-02` | 101.1 % | 57.4 % |
| `prod-ctrl-03` | 90.1 % | 38.3 % |
| `prod-work-02` | 101.1 % | 35.9 % |

The overhead measured above `maxmem` is 49 – 87 MB, up to about 2.2 % of a 4 GiB VM. 105 / 110 % leaves room for that and still alerts if a `kvm` process grows well beyond its assignment. Real memory pressure stays covered by the guest `Memory` check (80 / 90 %) and the Kubernetes checks. Before the rule, 14 days had 45 CRIT and 46 WARN alerts for `prod-ctrl-03` alone.

Root-cause fix: enable the balloon device in the Talos module, [isejalabs/terraform-proxmox-talos#296](https://github.com/isejalabs/terraform-proxmox-talos/issues/296); the 105 / 110 % rule is interim and is to be removed or tightened after that rollout. The rule for home VMs and containers (`container` folder, 99 / 100 %) exists for the same reason.

## Committed memory

`Memory` WARN "Committed > 100 %" on `dev-ctrl-01/03` and `dev-work-01` was already handled by the rule `e8ac31fb` (swapless nodes, `overcommit_memory=1`, `Committed_AS` structurally 2 – 3 times the commit limit); those services are OK on 2026-10-25. `tabea` (1.9 GiB, with swap) alerted three times in 14 days (WARN, CRIT, WARN) and is OK again at 59 %: left alone.

## Filesystem levels

Checkmk scales the filesystem levels by size ("magic factor"): the required free space is `level_free × (normsize / size) ^ (1 − magic)`. This reproduces the live values (`tabea /usr`, 4.48 GiB: 76.77 %; `polina`, 868 GiB: 86.28 %). With magic 0.9 and the default 20 GiB norm size, small filesystems were lowered to 74 / 87 % (`tabea /home`, 1.5 GiB) and caused WARNs that said nothing about the real headroom.

The global rule now uses magic 0.95 and a norm size of 1 GiB: nothing of 1 GiB or more gets levels below 80 / 90 %, larger filesystems still scale up, and filesystems below 1 GiB are lowered as before (down to the default floor of 50 / 60 %).

| Size | WARN / CRIT (% used), before | WARN / CRIT (% used), now |
| --- | --- | --- |
| 0.5 GiB | 71.1 / 85.5 | 79.3 / 89.6 |
| 1.5 GiB | 74.1 / 87.0 | 80.4 / 90.2 |
| 4.5 GiB | 76.8 / 88.4 | 81.4 / 90.7 |
| 20 GiB | 80.0 / 90.0 | 82.8 / 91.4 |
| 100 GiB | 83.0 / 91.5 | 84.1 / 92.1 |
| 868 GiB | 86.3 / 93.1 | 85.7 / 92.9 |

Disposition of the filesystems named in #1847 (values of 2026-10-25):

| Filesystem | Used | Verdict |
| --- | --- | --- |
| `hannelore /home` | 90.7 %, 11 days to full | **Real**: grows 3 GiB in 21 days; resize or clean up (owner action) |
| `tabea /usr` | 84.4 %, 0.7 GiB free, static | **Real but static**: still WARN; resize when convenient |
| `hannelore /usr` | 80.7 % | Noise, cleared (WARN level now 81.3 %); static |
| `tabea /home` | 74.4 % | Noise, cleared |
| `nsresolv1 /`, `mqtt /` | 78.5 % / 73.9 % | Noise, cleared; growth below 2 % in 21 days |
| `qa-ctrl-02 /` and other nodes | 77 – 79 % | See [below](#kubernetes-node-root-filesystem) |
| `polina` datastore | 86.4 %, 48 days to full | **Real, but a different cause**, see [below](#polina) |

### Kubernetes node root filesystem

The `/` of a node (Checkmk reads it from the node-collector pod; it is the XFS partition on `sdb1`, evidently Talos' ephemeral partition) holds the containerd images, kubelet data, logs and, on control-plane nodes, etcd. Disk sizes: 6 GiB for control-plane nodes (`ctrl_disk_size`), 12 GiB or 17 GiB for workers. The kubelet defaults (no override in this repository or in the Talos module): image garbage collection starts at 85 % used and frees down to 80 %; hard eviction at `imagefs.available < 15 %` (85 % used) or `nodefs.available < 10 %` (90 % used).

Under the old levels `qa-ctrl-02 /` flapped around its WARN level of 77.4 %: 209 hard WARN alerts in 14 days (`dev-ctrl-03` 72, `prod-ctrl-03` 49), although the usage was steady at about 78 %. The node rule sets WARN 86 % and CRIT 91 %, one point above the GC trigger and the node-filesystem eviction threshold, with no size scaling, so a normal GC cycle does not alert; the 15 minute notification delay on the Kubernetes sites does the rest.

The 6 GiB control-plane disks have little room: 78 % used is 0.9 GiB below the WARN level. Growing `ctrl_disk_size` is tracked in [#1909](https://github.com/isejalabs/homelab/issues/1909).

## Polina

The datastore growth is not a retention problem. PBS prune (`keep-last 3`, daily 7, weekly 4, monthly 12, yearly 3) and the weekly GC work: the GC of 2026-10-23 removed 49 GiB. The space is not returned because 156 `zrepl_*` ZFS snapshots hold 357 GiB of the 750 GiB used, as zrepl keeps every snapshot that was not replicated, and the replication to `pi4` has been failing since 2025-11-15 (expired certificates). Tracked in [#1905](https://github.com/isejalabs/homelab/issues/1905); the quick workaround to free space is [#1906](https://github.com/isejalabs/homelab/issues/1906). The PBS retention stays as it is.

## Open points

- Control-plane disk size (6 GiB): [#1909](https://github.com/isejalabs/homelab/issues/1909).
- `pve5` is excluded from the global filesystem rule (ZFS pools); the owner removes that exclusion.
