# Proxmox VM Snapshots & Rollback

## Overview

[#1296](https://github.com/isejalabs/homelab/issues/1296): a `just proxmox::*` recipe set that snapshots or
rolls back every VM belonging to one environment "in one go", via the Proxmox REST API -- no SSH to
individual Proxmox nodes, no hand-picking `70081<env-id><n>` VM IDs.

```sh
just proxmox::list -e dev                                # read-only: VMs + their snapshots
just proxmox::snapshot -e dev --name initial              # default --name is "initial"
just proxmox::rollback -e dev --name initial              # destructive -- see below
```

This operates one level below Kubernetes/Flux entirely -- it's talking directly to the Proxmox hypervisor
about the VMs Terraform provisioned (`terragrunt/<tier>/eu-central-1/<env>/vehagn-k8s/`), not to anything
inside the cluster. A rollback discards Talos/Kubernetes state right along with everything else on disk,
same as physically reverting the VM's disk would.

## Credential reuse

There's no separate Proxmox credential for this. `scripts/lib/proxmox.sh` decrypts
[`terragrunt/global-secrets.sops.yaml`](../terragrunt/global-secrets.sops.yaml) and reuses its
`proxmox_api_token` -- the exact same `bpg/proxmox`-formatted token (`user@realm!tokenid=secret`) that
Terraform already uses to *create and destroy* these VMs (`terragrunt/_envcommon/vehagn-k8s.hcl`). Reusing
it introduces no new credential and no new trust boundary: it's already trusted with strictly more power
than snapshot/rollback needs. Required token privileges (implied by, not additional to, its existing
create/destroy role): `VM.Snapshot`, `VM.Snapshot.Rollback`, `VM.PowerMgmt`, `VM.Audit`.

The token never touches disk in plaintext -- decrypted straight into a shell variable via `sops -d`, and
passed to `curl` through a `chmod 600` temp config file (`--config`, not a plain `-H` flag) so it isn't
visible to other local users via `ps`. TLS verification follows the secret's own `proxmox.insecure` flag,
the same trust decision the Terraform provider already encodes for this token/endpoint pair.

## VM discovery

Each environment's VMs are found by matching **both** of:

- **vmid** against the documented `70081<env-id><n>` scheme
  ([`docs/architecture/environments.md`](architecture/environments.md#environment-id)) -- the env-id lookup
  lives in `proxmox_env_id()` in `scripts/lib/proxmox.sh`, kept in sync with that doc's table by hand (same
  precedent as that doc's other consumer, the per-env `localASN: 6452<id>` hardcoded into each
  `k8s/infra/kube-system/cilium/envs/<env>/bgp-cluster-config.yaml`).
- **name prefix** `<env>-` on the VM itself, queried live from Proxmox's `/cluster/resources`.

A vmid match without the matching name prefix is logged and excluded rather than trusted -- defense in
depth, so a stale id mapping or a vmid collision can't silently touch another environment's VM.

## Rollback is destructive and gated

`rollback` requires typing the environment name to confirm (or `--yes` to skip that, e.g. non-interactive
use) before touching anything -- it discards every disk change made since the snapshot. `snapshot` and
`list` need no confirmation: creating a snapshot is additive, listing is read-only.

### Only the latest snapshot can be rolled back to

Proxmox's own rollback semantics (independent of which storage plugin backs the disk, so this applies to
this repo's `local-enc` datastore the same as anywhere else) refuse to roll a VM back to a snapshot that
isn't its **most recent** one -- if you've taken a newer snapshot (e.g. `bootstrapped`) on top of the one
you're targeting (e.g. `initial`), Proxmox rejects the rollback outright. The Proxmox API does expose a
`force` parameter that overrides this by destroying the intervening newer snapshots as part of the
rollback -- `scripts/proxmox-vm-rollback.sh` **deliberately doesn't expose it**: that's a second, larger
destructive action (irreversibly deleting other snapshots) layered on top of the one this issue asked for.

`rollback`'s pre-flight checks every discovered VM's snapshot list *before touching any of them*: the
target name must exist and be the newest entry on every VM, all-or-nothing. If it isn't, the command aborts
and names exactly which VMs have a newer snapshot on top and what it's called -- remove those first (via
the Proxmox UI/API) or pick a different `--name`.

> Verified live against `dbg` during this feature's development: `list`, `snapshot` (including the
> already-exists guard), and this latest-only pre-flight all behave exactly as described -- taking a second,
> newer snapshot and then targeting the older one is correctly refused before touching either VM. **Not yet
> exercised live: the actual rollback execution path** (stop, rollback, start) and the typed-confirmation
> prompt -- that needs its own deliberate, consented test run (it stops and restarts real VMs), not one
> folded into general development testing.

### Snapshot naming

Validated client-side before any API call, mirroring (not replacing) Proxmox's own `pve-configid`-style
schema: starts with a letter, digit, or underscore, followed by letters/digits/underscores/hyphens -- the
same shape as an existing Proxmox id already in this repo, e.g. the `local-enc` storage id. `current` is
rejected outright -- it's Proxmox's own reserved name for a VM's live, uncommitted state, never a real
snapshot.

## What each command does

- **`list`** (`scripts/proxmox-vm-list.sh`) -- discovers the environment's VMs and, for each, its
  snapshots (name + taken-at, from Proxmox's `snaptime`). Read-only.
- **`snapshot`** (`scripts/proxmox-vm-snapshot.sh`) -- pre-checks no discovered VM already has a snapshot
  of the target name, then creates one on every VM **in parallel** (a ZFS/PVE snapshot is a fast
  metadata-only operation, so concurrent VMs are low-risk here).
- **`rollback`** (`scripts/proxmox-vm-rollback.sh`) -- runs the pre-flight above, prompts for confirmation,
  then processes VMs **sequentially, one at a time**: stop it if running (hard stop -- a graceful shutdown
  is pointless when the disk is about to be reverted anyway), roll back, then start it again unless
  `--no-start`. Stops attempting further VMs after the first failure, reporting which VMs were already
  rolled back, which failed, and which weren't attempted yet.

## Known follow-ups (not yet implemented)

- **Host-grouped parallel rollback.** `rollback`'s stop+rollback+start(+VM boot) cycle is the slow part of
  this whole workflow, and multiple physical Proxmox hosts are usually involved. A faster design: group
  the discovered VMs by their Proxmox `node`, run one worker per node in parallel, and within each node's
  worker, kick off every one of that node's VM operations before waiting/polling for any of them -- v1
  above just runs fully sequential instead, being the simpler baseline to get right first.
- **`--force` rollback past a newer snapshot** -- see above; deliberately out of scope for the version
  described here.
