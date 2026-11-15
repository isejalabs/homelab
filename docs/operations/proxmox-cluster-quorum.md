---
status: current
---

# Proxmox cluster quorum: only pve1, pve4 and pve5 vote

Which Proxmox nodes count towards corosync quorum, why, and how to change it. The cluster `ISEJA-Lab` has five members; three of them (`pve1`, `pve4`, `pve5`) run permanently and host the standing Kubernetes environments, the other two (`pve3`, `pve6`) are worker nodes that are often powered off. Tracked in [#2322](https://github.com/isejalabs/homelab/issues/2322).

The Proxmox hosts are not managed in this repository, so there is no code to change: the configuration lives in `/etc/pve/corosync.conf` on the cluster itself, and this page is its record.

## At a glance

| | |
| --- | --- |
| When to use | Adding or removing a Proxmox node, or changing which nodes count towards quorum. Not for Talos/Kubernetes nodes (see [`node-lifecycle.md`](node-lifecycle.md)). |
| Prerequisites | Root SSH to a quorate Proxmox node (`/etc/pve` is read-only without quorum). |
| Steps | [Change which nodes vote](#change-which-nodes-vote), [Add a worker node](#add-a-worker-node). |
| Verify | [Verify](#verify) |
| Rollback | [Rollback](#rollback) |
| Last exercised | 2026-11-15 on the live cluster: `pve3` and `pve6` changed from 1 vote to 0, `config_version` 33 to 34 (see [Recorded state](#recorded-state)). |

## Why only three voters

Every node had 1 vote, so the five members gave `Expected votes: 5` and a quorum of 3. With only the three always-on nodes online, the cluster sat exactly at the threshold: losing any one of them meant no quorum, and `/etc/pve` turned read-only.

With `quorum_votes: 0` on `pve3` and `pve6`, the three voters have 3 votes and need 2. Any single voter can fail or be rebooted without losing quorum, and the worker nodes can be on or off freely. A zero-vote node is a full cluster member (it appears in the UI, can run guests and migrate them), but it only operates while the voters are quorate.

Three voters tolerate one failure; a fourth always-on node would not raise that (four voters still tolerate one), a fifth would tolerate two.

## Change which nodes vote

Edit a copy of the config, then move it into place, so that a half-written file is never read by corosync. On any quorate node:

```sh
cp /etc/pve/corosync.conf /root/corosync.conf.bak-<date>-v<old-version>
cp /etc/pve/corosync.conf /root/corosync.conf.new
```

In `/root/corosync.conf.new`, set `quorum_votes` in the `nodelist` entry of each node whose vote changes and raise `config_version` in the `totem` section by 1 (corosync only accepts a higher version). Check the difference, then apply it:

```sh
diff /root/corosync.conf.bak-<date>-v<old-version> /root/corosync.conf.new
mv /root/corosync.conf.new /etc/pve/corosync.conf
```

`mv` may print `failed to preserve ownership` on `/etc/pve`; that is harmless on the cluster file system, the file is in place.

> [!WARNING]
> Count the votes of the nodes that stay online after the change: they must reach the new quorum, or the cluster loses it immediately. Removing the vote of a node that is offline anyway is safe; removing the vote of an online voter is not.

## Add a worker node

`pvecm add` gives the new node 1 vote. To keep it a non-voter, set `quorum_votes: 0` for it with the procedure above straight after it has joined. Until then the expected votes (and the quorum threshold) are one higher.

## Verify

On each voter:

```sh
pvecm status
grep config_version /etc/corosync/corosync.conf
```

Expect `Quorate: Yes`, the new `config_version`, `Expected votes: 3` and `Quorum: 2`. The membership list shows only the online nodes; a worker node that joins later is listed with 0 votes.

## Rollback

Copy the backup over `/etc/pve/corosync.conf` with `config_version` raised above the current value (corosync ignores a lower or equal version). This needs a quorate node.

## If quorum is lost

With two of the three voters down, the cluster is not quorate. `pvecm expected 1` on the surviving node makes it quorate again so `/etc/pve` becomes writable; this is the documented Proxmox emergency step and has not been exercised here. Revert it by bringing the other voters back, and do not leave a node running on a lowered expectation.

## Recorded state

| | Before | After |
| --- | --- | --- |
| Voters | `pve1`, `pve3`, `pve4`, `pve5`, `pve6` (1 vote each) | `pve1`, `pve4`, `pve5` (1 vote each); `pve3`, `pve6` 0 votes |
| `Expected votes` / `Quorum` | 5 / 3 | 3 / 2 |
| `config_version` | 33 | 34 |

Applied on 2026-11-15 with `pve1`, `pve4` and `pve5` online and `pve3` and `pve6` off. All three voters reported the new version and stayed quorate. The first time `pve3` and `pve6` rejoin they are expected to pick up version 34 and show 0 votes; that is still to be confirmed ([#2322](https://github.com/isejalabs/homelab/issues/2322)).
