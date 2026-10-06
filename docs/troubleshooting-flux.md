---
status: current
---

# Troubleshooting: Flux reconciliation

For whoever's responding to an incident where something isn't reconciling — not an introduction to how Flux fits into this repo (see [`architecture/overview.md`](architecture/overview.md) and [`architecture/kustomize.md`](architecture/kustomize.md) for that) and not the full cluster-rebuild sequence (see [`disaster-recovery.md`](disaster-recovery.md) for that).

## 1. Survey state first

```sh
flux get ks -A
flux get hr -A
```

Real example output shape (from [`k8s/bootstrap/README.md`](../k8s/bootstrap/README.md#flux-cd)):

```
NAMESPACE  	NAME                   	REVISION                     	SUSPENDED	READY	MESSAGE
flux-system	longhorn-core          	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	longhorn               	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
```

Every `Kustomization`/`HelmRelease` in this repo lives in the `flux-system` namespace regardless of which namespace it actually deploys into — that's where Flux's own objects live, not the workload.

## 2. Classify what you're looking at before touching anything

A row that isn't `READY=True` is one of three different situations, and they need different responses:

### a. `SUSPENDED=True`

Someone (or an in-progress [kopiur restore](kopiur-backup-restore.md), which suspends a Kustomization/HelmRelease deliberately for the duration of the restore) paused it on purpose. Confirm there's no restore or other deliberate maintenance in progress before resuming — resuming mid-restore is exactly the mistake that doc's own gotchas section warns about:

```sh
flux resume kustomization <name>
# or:
flux resume helmrelease <name> -n <namespace>
```

### b. `READY=False`, message names another resource as not ready yet

Check [`dependsOn`](https://fluxcd.io/flux/components/kustomize/kustomizations/#dependencies) first — a real example from this repo, [`k8s/infra/longhorn-system/longhorn/flux/ks.yaml`](../k8s/infra/longhorn-system/longhorn/flux/ks.yaml):

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

Common real causes: a manifest that fails `kubeconform`-equivalent validation live (should have been caught by [`kustomize-build.yml`](../.github/workflows/kustomize-build.yml) in CI already, so this usually means the running cluster's CRD version is older than what main now expects), a webhook rejecting the applied object (the kopiur admission-webhook conflict documented in [`kopiur-backup-restore.md`](kopiur-backup-restore.md#restore-an-app-from-its-latest-backup) is a real precedent for this shape of failure), or a missing/renamed dependency that `dependsOn` doesn't cover because it's a same-Kustomization resource ordering issue rather than a cross-Kustomization one.

## 3. Force a reconcile instead of waiting out the interval

```sh
flux reconcile kustomization <name> --with-source
flux reconcile helmrelease <name> -n <namespace>
```

`--with-source` matters for a `Kustomization` — it also re-fetches the `GitRepository` first, so a reconcile triggered right after pushing a fix doesn't still apply the previous revision.

## 4. HelmRelease-specific gotcha: `Ready=True` doesn't always mean live state matches git

Confirmed live (dev, rebuild) per [`kopiur-backup-restore.md`](kopiur-backup-restore.md#restore-an-app-from-its-latest-backup): `flux resume helmrelease`/a successful reconcile can report `Ready=True` while a field that's unchanged between the HelmRelease's two most recent revisions (typically `replicas`) still doesn't match git, because `helm upgrade` diffs against the *previous release's own declared values*, not live cluster state. If a Helm-based app looks reconciled but a specific field still looks wrong, check that field explicitly (`kubectl get <resource> -n <namespace> -o yaml`) rather than trusting `READY=True` alone for it.

## 5. If nothing above explains it: check what the environment is actually tracking

```sh
kubectl get gitrepository flux-system -n flux-system --context admin@<env>-homelab -o jsonpath='{.spec.ref}'
```

Expect `{"name":"refs/heads/main"}`. If it's anything else, this environment's `flux-instance` was pointed at a different branch for testing (see the [`track-branch`](../.agents/skills/track-branch/SKILL.md) skill) and the override was never reverted — every `Kustomization` in the environment reconciling against a stale/unmerged branch instead of `main` looks identical to "nothing's wrong, but the live state doesn't match what I expect from `main`". Revert the override (see that skill's step 4) before diagnosing anything else in this environment.

## Verify the fix actually took

Re-run `flux get ks -A`/`flux get hr -A` and confirm the specific row now shows `READY=True` with the revision you expect — not just that the `flux reconcile`/`resume` command itself exited `0`. For a HelmRelease, also re-check any field flagged by case 4 above explicitly, since `READY=True` alone doesn't cover it.
