---
status: current
---

# Disaster recovery

This composes already-documented, individually-verified procedures into one ordered path for recovering
the cluster, rather than duplicating any of them — each step below links to the doc that owns the actual
mechanism. Per [finding F8](audits/2026-09-documentation.md#f8--backup-documentation-should-emphasize-restore-capability)
of the documentation audit, this is explicit about what's actually been tested versus what's only expected
to work: **the full sequence below has not yet been run start-to-finish as one timed rehearsal and recorded
here** — individual pieces have (kopiur's restore path was validated directly in `rebuild` via a disposable
test app), but composing them has not. Treat the next `rebuild` exercise (see
[`environments.md`](architecture/environments.md#what-each-environment-is-for) for why that environment
exists) as the opportunity to actually run this procedure and update this paragraph with the result.

## Recovery scenarios

| Scenario | Mechanism | Tested end-to-end? |
| --- | --- | --- |
| Whole cluster lost (Proxmox VMs, Talos, Kubernetes all gone) | [Full cluster rebuild](#full-cluster-rebuild) below | No — composed from tested pieces, not yet rehearsed as one sequence |
| In-cluster app data lost (PVC deleted/corrupted, cluster otherwise fine) | [`kopiur-backup-restore.md`](kopiur-backup-restore.md#restore-an-app-from-its-latest-backup) | Yes — validated live in `rebuild` with a disposable test app |
| A single Proxmox VM/LXC lost (not the whole cluster) | Proxmox vzdump/PBS restore | Not yet documented at all — tracked at [#1509](https://github.com/isejalabs/homelab/issues/1509) |
| A `proxmox-csi` volume's data needs to survive the rebuild below | [`storage.md`](architecture/storage.md#proxmox-csi--terragrunt-pinned-volumes-that-survive-a-cluster-rebuild) | Yes — this is the property proxmox-csi is specifically kept for |
| Root-zone DNS (the two LXC nameservers) lost | Outside this repo entirely — see [`network.md`](architecture/network.md#physical-network-opnsense-ucs-and-the-root-nameservers) | Not covered here |

## Full cluster rebuild

Six steps, each citing the doc that owns it. Run them in order; don't skip a validation checkpoint to save
time — a problem caught at step 2 is much cheaper to fix than the same problem discovered at step 6.

### 1. Provision VMs and install Talos

[`AGENTS.md`](../AGENTS.md)'s Terragrunt section has the actual commands (`terragrunt plan`/`apply` from the
environment's `vehagn-k8s` module directory), the `.envrc`/`TG_IAM_ASSUME_ROLE` direnv gotcha for
non-interactive shells, and the `prod`/`qa` main-branch-only rule — not duplicated here.

**If recovering from a teardown that preserved Proxmox volumes** (rather than a from-scratch provision):
import the surviving disk(s) first — see [`terragrunt/README.md`](../terragrunt/README.md#import-proxmox-volume)'s
import commands, which need the Proxmox volume's node/storage path from before the teardown.

**Checkpoint**: don't proceed until the next step's own checks (below) pass — Terragrunt reports success at
the infrastructure level, but the node/pod-readiness check is the real signal the cluster is actually usable.

### 2. Import cluster access configs

[`terragrunt/README.md`](../terragrunt/README.md#import-configs) — merge the fresh `talosconfig`, generate a
`kubeconfig`. Remove any stale context for the same cluster name first if this is a rebuild of an
already-known environment (same doc, ["Remove existing contexts from config"](../terragrunt/README.md#remove-existing-contexts-from-config)),
or `kubectl config get-contexts` will show a confusing `-1`-suffixed duplicate.

**Checkpoint**: [`k8s/bootstrap/README.md`](../k8s/bootstrap/README.md#preliminary-checks)'s preliminary
checks — `kubectl get nodes -A -o wide` (all nodes `Ready`), then `kubectl get pods -A --field-selector=status.phase=Failed`
(expect none). Don't move to step 3 until both are clean.

### 3. Bootstrap CRDs, foundational infra, and hand off to Flux

[`k8s/bootstrap/README.md`](../k8s/bootstrap/README.md) — `just bootstrap::cluster --env <env>`. This
installs Cilium, sealed-secrets, cert-manager, the Flux operator/instance (see
[`workloads.md`](architecture/workloads.md#bootstrap-install-order) for the exact dependency chain), then
hands reconciliation off to Flux for everything else.

**Checkpoint**: the same doc's own `flux get ks -A` check — every `Kustomization` should reach `READY=True`
within a few reconcile intervals (see [`environments.md`](architecture/environments.md#2-how-updates-land)
for how long that takes per environment). A `Kustomization` stuck `False` here is a real problem to resolve
before continuing, not something later steps will fix on their own.

### 4. Verify in-cluster app/PVC data restored automatically

No restore command needed here — this isn't an action step, just a checkpoint. Every app's PVC uses
kopiur's CSI `dataSourceRef`/`Restore` populator
(see [`kopiur-backup-restore.md`'s "Restore-on-create"](kopiur-backup-restore.md#restore-on-create-the-core-idea)),
and step 3's Flux reconciliation creating each app's PVC fresh *is* the "full namespace recreation" case
that mechanism already handles on its own: kopiur restores the latest matching snapshot before any pod can
mount the volume, with no explicit restore command. This exact automatic-restore-on-create path is what the
disposable `kopiur-test` app validated live in `rebuild` (see the scenarios table above) — not the manual
recipe below.

**Checkpoint**: confirm each app's data is actually *present*, not just that its PVC is `Bound` — a PVC
whose `Restore` found no matching snapshot still binds successfully (`onMissingSnapshot: Continue` populates
an empty volume instead of blocking forever), which looks identical to a successful restore at the PVC
level. [`kopiur-backup-restore.md`'s manual restore recipe](kopiur-backup-restore.md#restore-an-app-from-its-latest-backup)
(`just backup::kopiur::restore <app> -e <env> -n <namespace>`) is only needed if this checkpoint fails for a
specific app — not part of the normal rebuild sequence.

### 5. Re-attach any `proxmox-csi`-pinned volumes

Only relevant if step 1's teardown deliberately preserved Proxmox-side disks for a `proxmox-csi` volume
(see the scenarios table) rather than a from-scratch provision — the import happened in step 1, but the
Kubernetes-side `PersistentVolume`/`PersistentVolumeClaim` binding is worth confirming explicitly here, once
the app that claims it is actually running (step 3/4 may have already recreated it). See
[`storage.md`](architecture/storage.md#proxmox-csi--terragrunt-pinned-volumes-that-survive-a-cluster-rebuild)
for which volumes this applies to today.

**Checkpoint**: `kubectl get pvc -A` shows the volume `Bound`, and the app using it has its data (the same
check as step 4, for the proxmox-csi case instead of the kopiur-backed case).

### 6. Final end-to-end check

No single existing doc covers this, since it's specific to "is the whole homelab actually back," not any
one subsystem:

- `flux get ks -A` and `flux get hr -A` — everything `READY=True`, nothing `SUSPENDED`.
- `kubectl get pods -A --field-selector=status.phase!=Running` — nothing unexpected (completed Jobs are
  fine, see [`k8s/bootstrap/README.md`](../k8s/bootstrap/README.md#preliminary-checks)).
- Spot-check at least one real, user-facing app end to end (e.g. a DNS query against AdGuard, or opening
  Actual Budget) — a clean `flux`/`kubectl` status doesn't guarantee the app is actually usable.

## What this doesn't cover yet

- A single Proxmox VM/LXC lost without the rest of the cluster — the vzdump/PBS restore procedure doesn't
  exist in writing yet; tracked at [#1509](https://github.com/isejalabs/homelab/issues/1509).
- Root-zone DNS recovery if both LXC nameservers are lost — physical infrastructure with no representation
  in this repo at all (see [`network.md`](architecture/network.md#physical-network-opnsense-ucs-and-the-root-nameservers)).
- A dated, timed record of having actually run the full sequence above — see the opening paragraph.
