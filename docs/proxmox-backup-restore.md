---
status: current
---

# Proxmox VM/LXC Backup & Restore (vzdump/PBS)

**Choose a restore path:** [restore to a new VMID](#restore-to-a-new-vmid-side-by-side-recovery) to validate recovery or preserve the current VM/LXC; [restore to the same VMID](#full-restore-to-the-same-vmid) when replacing a lost instance. Finish with [verification](#verify-the-restore-actually-took).

**On this page:** [PBS target and coverage](#the-pbs-target) · [Browse backups](#listingbrowsing-backups-for-a-given-vmlxc) · [Restore procedures](#restore-procedures) · [Verify the restore](#verify-the-restore-actually-took)

[#1509](https://github.com/isejalabs/homelab/issues/1509): every Proxmox VM/LXC in scope for this backup tier is backed up nightly via `vzdump` to a [Proxmox Backup Server](https://www.proxmox.com/en/proxmox-backup-server) target — but until now the actual **restore** procedure wasn't written down anywhere in this repo.

This is the backup/restore tier for when a whole VM/LXC is lost or corrupted, not just its application data — a different failure mode than anything else documented here:

- [`kopiur-backup-restore.md`](kopiur-backup-restore.md) — in-cluster PVC/application data (a pod's volume gets corrupted, the VM/node it runs on is fine).
- [`proxmox-vm-snapshots.md`](proxmox-vm-snapshots.md) — local Proxmox snapshots for the Terraform-managed `vehagn-k8s` environments (`dev`, `qa`, `prod`, etc.) — fast rollback on the same host, not an offsite backup.
- [`disaster-recovery.md`](disaster-recovery.md) — full cluster rebuild, which reprovisions those same `vehagn-k8s` environments from Terraform/Talos rather than restoring them from a backup at all.

**This doc's scope is deliberately the complement of all three**: the manually-managed "pet" VMs/LXCs — DNS servers, gateways, monitoring, mail relay, web front end, and similar — that aren't Terraform-reprovisionable and would be genuinely painful to lose. See [Why Talos K8s nodes aren't covered here](#why-talos-k8s-nodes-arent-covered-here) for why the two don't overlap.

## The PBS target

Configured once, cluster-wide, in `/etc/pve/storage.cfg` as storage ID `pbs`: a real external Proxmox Backup Server at `10.7.15.116`, datastore `polina1`, namespace `home.iseja.net`.

```sh
pvesh get /storage/pbs
```

## Backup schedule and coverage

The nightly schedule lives in `/etc/cron.d/vzdump` — identical on every Proxmox node (`pve1`/`pve4`/`pve6`), Proxmox-generated, **do not hand-edit** (change it via the Datacenter → Backup UI or `pvesh`/`pvenode` instead, so all nodes stay in sync):

```
10 23 * * *  root mk-job vzdump_crit vzdump --pool Crit --storage pbs --mode snapshot ...
20 23 * * *  root mk-job vzdump_prod vzdump --pool Prod --storage pbs --mode snapshot ...
30 23 * * *  root mk-job vzdump_test vzdump --pool Test --storage pbs --mode snapshot ...
```

Coverage is by **pool membership**, not "every VM" — only a VM/LXC that's a member of `Crit`, `Prod`, or `Test` gets backed up by this job. Check membership with:

```sh
pvesh get /pools/<Crit|Prod|Test>
```

### Why Talos K8s nodes aren't covered here

None of the `vehagn-k8s`-provisioned nodes (the `70081<env-id><n>`-numbered VMs across `dbg`/`dev`/`head`/`poc`/`qa`/`rebuild`/`src`/`prod`) are members of any of the three pools — confirmed live by listing all three pools' members. This is by design, not a gap: those VMs are Terraform-managed and fully reprovisionable (see [`disaster-recovery.md`](disaster-recovery.md)'s "Full cluster rebuild"), and the data that actually matters on them lives in Longhorn or kopiur, both of which have their own, independent backup mechanisms. A `k8s-test` pool exists but is currently empty — if Talos nodes are ever deliberately added to vzdump coverage in the future, that's presumably where they'd go, but as of this writing nothing does that.

## Listing/browsing backups for a given VM/LXC

```sh
pvesh get /nodes/<node>/storage/pbs/content --vmid <vmid>
```

Returns one entry per stored backup (`volid` like `pbs:backup/ct/<vmid>/<timestamp>Z` for an LXC, `pbs:backup/vm/<vmid>/<timestamp>Z` for a QEMU VM), its `format`/`subtype` (`pbs-ct`/`lxc` or `pbs-vm`/`qemu`), size, and a `verification.state` (`ok` once the separate verification job has checked it — a backup only a few days old may not have been verified yet, that's normal, not a problem). Sort by `ctime` to find the latest:

```sh
pvesh get /nodes/<node>/storage/pbs/content --vmid <vmid> --output-format json \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(sorted(d, key=lambda x: x['ctime'])[-1]['volid'])"
```

## Restore procedures

The two restore tools take their arguments in a **different order** from each other — easy to get backwards:

```sh
pct restore <vmid> <volid> [OPTIONS]      # LXC — new/target vmid first
qmrestore <volid> <vmid> [OPTIONS]        # QEMU VM — archive/volid first
```

### Restore to a new VMID (side-by-side recovery)

The safer option when the original still exists and you want to inspect/recover without touching it — this is what was actually tested live (see [Live-tested record](#live-tested-record-f8) below):

```sh
# LXC
pvesh create /nodes/<node>/lxc --vmid <new-vmid> --ostemplate '<volid>' --restore 1 --storage <storage> --hostname <name>

# or via pct directly on the node
pct restore <new-vmid> <volid> --storage <storage> --hostname <name>

# QEMU VM
qmrestore <volid> <new-vmid> --storage <storage>
```

Pick an unused VMID (check `pvesh get /cluster/resources --type vm` first). The restored VM/LXC comes back **stopped** — start it manually once you're ready (`pvesh create /nodes/<node>/lxc/<new-vmid>/status/start` or the `qm`/`pct` equivalent). If the original had a static IP baked into its config, consider whether the clone should get a different one before starting it alongside the original, to avoid an address conflict — DHCP-configured guests don't have this concern.

Clean up once done inspecting:

```sh
pvesh create /nodes/<node>/lxc/<new-vmid>/status/stop
pvesh delete /nodes/<node>/lxc/<new-vmid>
```

### Full restore to the same VMID

Use when the original is genuinely gone (destroyed) or you've deliberately decided to overwrite it. Requires `--force` if a VM/LXC with that ID still exists:

```sh
pct restore <vmid> <volid> --storage <storage> --force
qmrestore <volid> <vmid> --storage <storage> --force
```

This has **not** been tested live in this repo — only the new-VMID path above has. If a real same-VMID restore is ever needed, treat `--force` with real caution (it unconditionally replaces the existing guest's disk) and prefer snapshotting or at minimum confirming the existing guest is actually the one you intend to replace first.

## Live-tested record (F8)

Per [finding F8](audits/2026-09-documentation.md#f8--backup-documentation-should-emphasize-restore-capability) — this backup tier's restore path has now actually been exercised, not just assumed to work because backups exist and show `verification.state: "ok"`.

**2026-10-11**: restored `testlinux2.test.iseja.net` (LXC, VMID `7004056`, a member of the `Test` pool) from its latest PBS backup (`pbs:backup/ct/7004056/2026-10-10T21:34:38Z`) to a new VMID (`7004098`) on `pve1`/`local-zfs`, using the side-by-side procedure above. Confirmed genuinely usable, not just unpacked:

- Restore completed cleanly (2.576 GiB, ~2 minutes).
- Started successfully (`status: running`).
- `pct exec 7004098 -- hostname` / `cat /etc/os-release` / `uptime` all returned real, correct output from inside the restored container.
- Stopped and destroyed afterward, leaving no trace.

This validates the mechanism end to end for an LXC via the new-VMID path. The same-VMID (`--force`) path and a QEMU VM (as opposed to LXC) restore remain untested — if either is exercised for real, update this record.

## Verify the restore actually took

- `pvesh get /nodes/<node>/lxc/<vmid>/status/current` (or `/qemu/<vmid>/...`) shows `status: running` after starting it.
- `pct exec <vmid> -- <command>` (LXC) or console/SSH access (QEMU VM) confirms the restored content is real and matches what you expected — don't stop at "the restore command exited 0".
