---
status: current
---

# Troubleshooting: Flux reconciliation

For whoever's responding to an incident where something isn't reconciling — not an introduction to how Flux fits into this repo (see [`architecture/overview.md`](../architecture/overview.md) and [`architecture/kustomize.md`](../architecture/kustomize.md) for that) and not the full cluster-rebuild sequence (see [`disaster-recovery.md`](../backup/disaster-recovery.md) for that).

## 1. Survey state first

```sh
flux get ks -A
flux get hr -A
```

Real example output shape (from [`k8s/bootstrap/README.md`](../../k8s/bootstrap/README.md#flux-cd)):

```
NAMESPACE  	NAME                   	REVISION                     	SUSPENDED	READY	MESSAGE
flux-system	longhorn-core          	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	longhorn               	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
```

Every `Kustomization`/`HelmRelease` in this repo lives in the `flux-system` namespace regardless of which namespace it actually deploys into — that's where Flux's own objects live, not the workload.

## 2. Classify what you're looking at before touching anything

A row that isn't `READY=True` is one of three different situations, and they need different responses:

### a. `SUSPENDED=True`

Someone (or an in-progress [kopiur restore](../backup/kopiur-backup-restore.md), which suspends a Kustomization/HelmRelease deliberately for the duration of the restore) paused it on purpose. Confirm there's no restore or other deliberate maintenance in progress before resuming — resuming mid-restore is exactly the mistake that doc's own gotchas section warns about:

```sh
flux resume kustomization <name>
# or:
flux resume helmrelease <name> -n <namespace>
```

### b. `READY=False`, message names another resource as not ready yet

Check [`dependsOn`](https://fluxcd.io/flux/components/kustomize/kustomizations/#dependencies) first — a real example from this repo, [`k8s/infra/longhorn-system/longhorn/flux/ks.yaml`](../../k8s/infra/longhorn-system/longhorn/flux/ks.yaml):

```yaml
dependsOn:
  - name: longhorn-core
```

`longhorn` legitimately reports `READY=False`/`Unknown` for as long as `longhorn-core` hasn't reached `Ready` itself — that's Flux correctly refusing to apply a dependent resource early, not a bug in `longhorn`. Check the *named* dependency's own row in `flux get ks -A`/`flux get hr -A` first; if it's the one actually failing, diagnose that one instead (recurse into case (c) for it), and ignore the dependent's `READY=False` until the root cause clears — it should resolve itself on the next reconcile once the dependency does.

### c. `READY=False`, a real error message

Get more detail than the one-line `MESSAGE` column gives:

```sh
flux logs --kind=Kustomization --name=<name> -n flux-system
kubectl describe kustomization <name> -n flux-system
kubectl get events -n <workload-namespace> --sort-by=.lastTimestamp
```

Common real causes: a manifest that fails `kubeconform`-equivalent validation live (should have been caught by [`kustomize-build.yml`](../../.github/workflows/kustomize-build.yml) in CI already, so this usually means the running cluster's CRD version is older than what main now expects), a webhook rejecting the applied object (the kopiur admission-webhook conflict documented in [`kopiur-backup-restore.md`](../backup/kopiur-backup-restore.md#restore-an-app-from-its-latest-backup) is a real precedent for this shape of failure), or a missing/renamed dependency that `dependsOn` doesn't cover because it's a same-Kustomization resource ordering issue rather than a cross-Kustomization one.

## 3. Force a reconcile instead of waiting out the interval

```sh
flux reconcile kustomization <name> --with-source
flux reconcile helmrelease <name> -n <namespace>
```

`--with-source` matters for a `Kustomization` — it also re-fetches the `GitRepository` first, so a reconcile triggered right after pushing a fix doesn't still apply the previous revision.

## 4. HelmRelease-specific gotcha: `Ready=True` doesn't always mean live state matches git

Confirmed live (dev, rebuild) per [`kopiur-backup-restore.md`](../backup/kopiur-backup-restore.md#restore-an-app-from-its-latest-backup): `flux resume helmrelease`/a successful reconcile can report `Ready=True` while a field that's unchanged between the HelmRelease's two most recent revisions (typically `replicas`) still doesn't match git, because `helm upgrade` diffs against the *previous release's own declared values*, not live cluster state. If a Helm-based app looks reconciled but a specific field still looks wrong, check that field explicitly (`kubectl get <resource> -n <namespace> -o yaml`) rather than trusting `READY=True` alone for it.

**A `Stalled: RetriesExceeded` HelmRelease does not get retried by a plain `flux reconcile`.** Confirmed live, 2026-10-14: `cilium`'s HelmRelease had failed upgrading `1.18.13` -> `1.18.14` on `timeout waiting for: [DaemonSet/... status: 'InProgress']`, even though the live DaemonSet was already fully healthy at the new version (Helm's own release bookkeeping just never caught up). `flux reconcile helmrelease` immediately re-reported the same stale `Stalled`/`RetriesExceeded` status without attempting anything — only `flux suspend helmrelease` followed by `flux resume helmrelease` actually resets the retry counter and triggers a real attempt (which then resolved in seconds, since the DaemonSet had nothing left to change). Worth checking for proactively: a stuck HelmRelease like this silently blocks every Kustomization that depends on it via `dependsOn`, for as long as nobody notices.

Since [#2045](https://github.com/isejalabs/homelab/issues/2045) the `flux-instance` HelmRelease enables helm-controller's `DefaultToRetryOnFailure` feature gate ([`k8s/infra/flux-system/flux-instance/base/helmrelease.yaml`](../../k8s/infra/flux-system/flux-instance/base/helmrelease.yaml)): a failed install or upgrade is retried every 5 minutes (the default `retryInterval`) without a retry budget instead of ending in `Stalled`. A slow cold bring-up (image pulls outlasting the 5-minute Helm timeout) should therefore converge on its own, and the `Stalled`/`RetriesExceeded` case above should only show up on a cluster where the gate is not active yet (check with `kubectl get deploy helm-controller -n flux-system -o jsonpath='{.spec.template.spec.containers[0].args}'`). The manual reset stays the way out there.

## 5. A Kustomization reconcile deadlocked mid-flight, not just failing

A row that's `READY=Unknown`/`Reconciling: True` for far longer than its usual interval — not `False` with an error, and not caught by case 2 above — can mean the *current* reconcile attempt is genuinely wedged, not slow. This happens when the Kustomization's health check is polling a resource (e.g. a PVC) that gets deleted out-of-band while that same reconcile call is still running: the call blocks inside its health-check wait (up to `spec.timeout`, e.g. `59m30s`) for a resource that will never reappear on its own, and every later `flux suspend`/`resume`/`reconcile --with-source` request just gets queued behind it — annotated, accepted, but never actually serviced — until that one call's timeout finally elapses.

Confirm this before trying anything else:

```sh
kubectl get kustomization <name> -n flux-system -o jsonpath='{.metadata.generation}{" obs="}{.status.observedGeneration}{"\n"}'
kubectl -n flux-system logs deploy/kustomize-controller --since=10m | jq -r 'select(.Kustomization.name=="<name>") | "\(.ts) \(.msg)"'
```

A growing gap between `generation` (bumped by every suspend/resume toggle and reconcile-annotation request) and `observedGeneration` (stuck), with no new `"server-side apply completed"` log line appearing for that Kustomization despite those requests, confirms a wedged call rather than a slow or failing one.

**Fix: restart the controller, don't keep retrying `resume`/`reconcile`.**

```sh
kubectl -n flux-system rollout restart deployment/kustomize-controller
```

This kills the stuck in-process reconcile and makes the controller re-list and re-reconcile everything fresh on startup — routine, no resource or data changes, and the few-second restart briefly pauses reconciliation cluster-wide for that environment. Confirmed live, 2026-10-14: `observedGeneration` caught up to `metadata.generation` within seconds of the restart, and the queued apply (recreating a deleted PVC) ran immediately after.

## 6. If nothing above explains it: check what the environment is actually tracking

```sh
kubectl get gitrepository flux-system -n flux-system --context admin@<env>-homelab -o jsonpath='{.spec.ref}'
```

Expect `{"name":"refs/heads/main"}`. If it's anything else, this environment's `flux-instance` was pointed at a different branch for testing (see the [`track-branch`](../../.agents/skills/track-branch/SKILL.md) skill) and the override was never reverted — every `Kustomization` in the environment reconciling against a stale/unmerged branch instead of `main` looks identical to "nothing's wrong, but the live state doesn't match what I expect from `main`". Revert the override (see that skill's step 4) before diagnosing anything else in this environment.

## Verify the fix actually took

Re-run `flux get ks -A`/`flux get hr -A` and confirm the specific row now shows `READY=True` with the revision you expect — not just that the `flux reconcile`/`resume` command itself exited `0`. For a HelmRelease, also re-check any field flagged by case 4 above explicitly, since `READY=True` alone doesn't cover it.
