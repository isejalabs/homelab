---
name: track-branch
description: Point one or more environments' Flux instance at a git branch instead of main, to test an unmerged change/app in a real cluster — edits k8s/infra/flux-system/flux-instance/envs/<env>/helmrelease.yaml's sync.ref and commits it as a throwaway tmp(<env>) commit to revert later.
---

# Track a branch in an environment's Flux instance

Every environment's cluster is normally synced from `refs/heads/main` (the default set in
`k8s/infra/flux-system/flux-instance/base/helmrelease.yaml`'s `spec.values.instance.sync`). To test an
unmerged change or new app in a real cluster before merging, override that ref for one environment at
a time via a commented-out placeholder already present in each env overlay.

## 0. Resolve inputs

Ask only for what the request doesn't already say:
1. **Environment(s)**: one or more of `dbg`, `dev`, `head`, `poc`, `qa`, `rebuild`, `src` (not `prod`).
   Never default this silently — always ask which env(s) to target unless the request already names
   them (e.g. "track the current branch in qa", "change dev to track branch X").
2. **Branch**: defaults to the current branch (`git branch --show-current`) if the request says "the
   current branch" or doesn't mention one at all. If it names a different branch, use that instead —
   don't assume it exists locally, `git rev-parse --verify <branch>` first if unsure.

## 1. Edit the env overlay

File: `k8s/infra/flux-system/flux-instance/envs/<env>/helmrelease.yaml`. It has a commented-out `ref:`
line under `spec.values.instance.sync` (or an already-active one from a prior override):

```yaml
      sync:
        path: "k8s/bootstrap/cluster/flux/envs/<env>"
        # Uncomment f. line to use a specific branch for this environment
        # ref: "refs/heads/issue/123_XY-branch"
```

Set it to:

```yaml
        ref: "refs/heads/<branch>"
```

Only touch the `ref:` line — leave `path:`, `interval:` (where present), and the explanatory comment
above it untouched. Repeat per requested environment.

## 2. Commit

**Commit this onto the branch being tracked itself — never onto `main`.** `main` is what every other
environment reconciles from; a `tmp(...)` override pushed there would be live for all of them, not just
the one being tested, and it's the kind of direct-to-`main` push that should never happen. Since the
override's whole point is to make an environment follow a branch other than `main`, the commit
belongs on that branch, where it's self-contained and disappears once the branch is deleted/merged.

Amend/add it onto the existing feature branch (or, if there is no branch yet, create one from the
current commit first) — staging only that env's `helmrelease.yaml`. The established convention here is
a deliberately non-Conventional-Commits `tmp(...)` type, marking the commit as throwaway and meant to
be reverted once testing is done — do not fold it into a real `feat`/`fix`/`chore` commit:

```
tmp(<env>): track dev branch
```

Note: the subject is a fixed phrase — "dev branch" here means *a development/testing branch*, not
literally the `dev` environment. Don't reword it to name the actual branch or environment; two prior
commits (`tmp(dev): track dev branch`, `tmp(qa): track dev branch`) established this exact wording as
the convention.

You can push the commit (to the feature branch) automatically.

## 3. Apply directly to the live cluster

Pushing the branch to GitHub is not enough by itself: the target environment's `GitRepository` is
still pinned to whatever ref its `flux-instance` `HelmRelease` currently specifies (normally `main`),
so it will never notice a commit that only exists on another branch. The environment has to be told,
right now, to point at the new ref — which happens by applying the edited overlay straight to the
live cluster, bypassing the normal git-push-and-wait-for-reconciliation flow entirely:

```sh
kubectl apply -k k8s/infra/flux-system/flux-instance/envs/<env> --context admin@<env>-homelab
```

This updates the live `flux-instance` HelmRelease and its `OCIRepository`; the flux-operator then
rewrites the environment's `GitRepository.spec.ref` to match. Confirm it took:

```sh
kubectl get gitrepository flux-system -n flux-system --context admin@<env>-homelab -o jsonpath='{.spec.ref}'
```

Expect `{"name":"refs/heads/<branch>"}`. The `GitRepository`'s *status* (last stored revision) only
catches up on its next reconcile interval (typically 1m) — don't mistake a stale status for failure.

Run this `kubectl apply -k` for every environment being switched. `admin@<env>-homelab` is the kubectx
naming convention used throughout this repo (verify with `kubectl config get-contexts` if unsure).

## 4. Reverting later

Once testing is done and before merging the branch, the override must be undone so the environment
falls back to tracking `main`. Restore the line to its commented placeholder form (or drop the `ref:`
line entirely and re-add the comment), commit that (again on the feature branch, not `main` — no
wording convention exists yet for this commit, so ask the user what message they want rather than
guessing one), then re-run the same `kubectl apply -k ... --context admin@<env>-homelab` from step 3
so the live cluster actually flips back to `main` immediately rather than waiting to merge.
