# Agent Instructions

@.commons/agents/AGENTS.common.md

## What this repo is

A personal, IaC-driven homelab: Proxmox VMs → Talos Linux → Kubernetes, provisioned with OpenTofu/Terragrunt and reconciled with Flux CD. Everything is DRY across 8 environments (`dbg`, `dev`, `head`, `poc`, `prod`, `qa`, `rebuild`, `src`) via a shared kustomize "components" layer.

## Repository layout

- `terragrunt/` — OpenTofu/Terragrunt IaC that provisions Proxmox VMs and installs Talos. Structure is `terragrunt/<non-prod|prod>/<account>/<region>/<env>/<module>`.
   - `terragrunt/_envcommon/` holds reusable `.hcl` includes (`vms.hcl`, `talos-proxmox.hcl`, `vehagn-k8s.hcl`, `tf-state-read-role.hcl`).
   - `terragrunt/root.hcl` is the top-level config: it merges `account.hcl`/`region.hcl`/`env.hcl` locals and SOPS-encrypted `*-secrets.sops.yaml` at each level (global → account → region → env → local, each overriding the last), and wires the S3 remote-state backend.
- `k8s/bootstrap/` — the second bootstrap phase: `helmfile` installs foundational CRDs and infra (Cilium, sealed-secrets, cert-manager, external-secrets, onepassword-connect, flux-operator/instance) via `just bootstrap::cluster --env <env>`, then hands off to Flux. `k8s/bootstrap/cluster/flux/` defines the Flux `sets/` (`infra`, `apps`, each with `minimal`/`optional` subsets) that get composed per environment under `flux/envs/<env>/`. `k8s/bootstrap/helmfile/` has the helmfile definitions (`crds/`, `apps/`, `base/`, `templates/*.gotmpl`). `k8s/bootstrap/kustomize/personal/` holds personal credentials injected via `op inject` during bootstrap. See `k8s/bootstrap/README.md` for the full walkthrough and prerequisites.
- `k8s/infra/` and `k8s/apps/` — the actual workloads Flux reconciles, grouped by domain (e.g. `k8s/infra/cert-manager/`, `k8s/infra/csi-proxmox/`, `k8s/apps/dns/adguard/`, `k8s/apps/finances/actualbudget/`). Every app/infra unit follows the same shape:
  - `base/` — environment-agnostic manifests (a `kustomization.yaml` plus resources, using placeholder domain `example.com`).
  - `envs/<env>/` — per-environment overlay: pulls in `../../../../../components/envs/<env>` as a kustomize component and patches (`patches:`) only what differs (Service LB IPs, replica counts, etc.).
  - `flux/` — the Flux `Kustomization` (`ks.yaml`) that tells Flux to reconcile this unit, plus its own `kustomization.yaml`. Note `spec.path` in `ks.yaml` is written pointing at `base/` but gets rewritten per-environment (see below).
- `k8s/components/` — the shared DRY layer. `components/envs/<env>/` are the per-environment kustomize Components included by every app/infra overlay. `components/transformers/` holds the actual kustomize transformers/replacements those components apply:
  - `replace-path` — rewrites the last two path segments of every Flux `Kustomization.spec.path` (`.../base` → `.../envs/<env>`) using `ConfigMap` values `cluster-base-param`/`cluster-param` (`CLUSTER_ENVIRONMENT`), driven by `components/envs/base/cluster-base-param.yaml` and `components/envs/<env>/cluster-param.yaml`.
  - `replace-domain` / `prefix-domain` — swap the placeholder `example.com` for the real domain (and prefix per-env, e.g. `dev-app.example.com`) across Ingress/HTTPRoute/TLSRoute/Gateway/Certificate resources.
  - `add-labels` — adds common labels (e.g. `reconcile.fluxcd.io/watch: "Enabled"`).
  - `set-flux-defaults` — sets default Flux `Kustomization`/`HelmRelease` reconciliation intervals.
  - `kopiur-secret-env` — rewrites `kopiur-repository`'s per-env 1Password key and `ClusterRepository` bucket name (both otherwise stated once, generically, in `base/`).
  - `suspend-kopiur-schedule` — force-suspends every `SnapshotSchedule` in environments without an active kopiur backup schedule (`dbg`/`head`/`poc`/`src`), regardless of which storage component an app picked.
  See `k8s/components/README.md` for the folder structure.
- `scripts/` — helper shell scripts: `sops-encrypt-all.sh`/`sops-decrypt-all.sh` (bulk SOPS operations), `tg-state-rm.sh` (remove dangling/volume Terragrunt state before destroy), `volume-remove-state.sh`, `upgrade-k8s.sh`.
- `_attic/`, `ZZ.bak/` — retired/old material, not part of the active implementation.

## Commands

Root command runner is [`just`](https://github.com/casey/just) (`.justfile`), which imports the `bootstrap` module from `k8s/bootstrap/mod.just`.

```sh
# Bootstrap (or re-sync) a cluster's core CRDs + foundational infra apps for one environment
just bootstrap::cluster --env <dbg|dev|head|poc|prod|qa|rebuild|src>
```

This runs two private sub-recipes in order:
- `core` (namespaces and personal credential injection via `op inject` leveraging `k8s/bootstrap/kustomize`, as well as CRD extraction/apply from helmfile — see `k8s/bootstrap/helmfile/crds/helmfile.yaml.gotmpl`)
- `apps` (helmfile sync of Cilium, sealed-secrets, cert-manager, external-secrets, onepassword-connect, flux-operator, flux-instance — see `k8s/bootstrap/helmfile/apps/helmfile.yaml.gotmpl` for the authoritative list and ordering). After that, Flux CD takes over reconciliation from Git automatically — there is no separate "apply everything" command for `k8s/infra`/`k8s/apps`; changes land by being merged and reconciled by Flux (`flux get ks -A` to check status).

**Testing a not-yet-merged branch against a live environment**: see the `track-branch` skill
(`.agents/skills/track-branch/`) — points one environment's `flux-instance` at a branch via a `tmp(<env>): ...`
commit made *on that same branch* (never `main`, never a separate branch) plus a direct `kubectl apply -k`
to the live cluster. Fine for any non-prod environment (`dbg`, `dev`, `head`, `poc`, `qa`, `rebuild`, `src`)
— never `prod`. Clean up any test-created resources afterward, including
Retain-policy PVs/Longhorn volumes, which outlive the PVC/namespace that claimed them and need deleting
both as the k8s `PersistentVolume` object and the underlying `volumes.longhorn.io` object.

Terragrunt (run from `terragrunt/<non-prod|prod>/<account>/<region>/<env>/<module>`):

```sh
cd terragrunt/non-prod/eu-central-1/dev/vehagn-k8s
terragrunt plan
terragrunt apply
```

Each environment directory has an `.envrc` (e.g. `terragrunt/non-prod/eu-central-1/dev/.envrc`) that exports `TG_IAM_ASSUME_ROLE`, the per-env state-read/write role terragrunt assumes for the S3 remote-state backend. `direnv` loads this automatically on `cd` in an interactive shell — but a non-interactive agent shell (no direnv hook) must `source` that `.envrc` itself before running `terragrunt plan`/`apply`, or every command fails with a generic S3 `HeadObject`/`403 Forbidden` on state access (easy to misdiagnose as an unrelated AWS credentials problem).

**Apply from `main`, not a feature branch.** `prod` and `qa` may *only* ever be applied from a `main` checkout — no exceptions. For the other envs, applying from a feature branch to validate a not-yet-merged change is acceptable, but treat it as temporary the same way the `track-branch` skill's live Flux testing is temporary — merge the branch promptly afterward so the next apply (from `main`) is a no-op, rather than leaving real state hanging indefinitely on an unmerged branch. Unlike that skill's live `kubectl` override, there's no equivalent one-command revert here: a `terragrunt apply` from a branch creates real state that only matches an *unmerged* branch, and the only way back in sync is merging it, not pointing back at `main`. That asymmetry is exactly why `prod`/`qa` don't get the temporary exception at all.

SOPS:

```sh
scripts/sops-encrypt-all.sh    # re-encrypt all *.sops.yaml under current SOPS rules
scripts/sops-decrypt-all.sh
```

Pre-commit hooks (`.pre-commit-config.yaml`) enforce: no unencrypted secrets committed (`forbid-secrets`, with a single deliberate exception at `k8s/bootstrap/kustomize/personal/external-secrets/s3cr3t.yaml`) and valid SOPS encryption on `*.sops.{yaml,json,env}` files (`validate-sops`).

There is no build/lint/test suite (no application source code) — validation is via `pre-commit`, `kustomize build`/`helmfile template` (used implicitly by `just bootstrap::cluster`), and Flux's own reconciliation status.

## Conventions

- **Secrets never live in Git in plaintext.** Two mechanisms: SOPS (`.sops.yaml`, age-encrypted) for Terragrunt `*-secrets.sops.yaml` and select `k8s/**/*.sops.yaml`/`*.auto.tfvars`, and 1Password (`op://` references resolved via `op inject`) for in-cluster secrets, later handed off to [External Secrets Operator](https://external-secrets.io/). Never hand-edit an already-encrypted `*.sops.yaml` file directly — decrypt, edit, re-encrypt (or use the `scripts/sops-*-all.sh` helpers).
- **Adding/changing a k8s app or infra component**: edit `base/` for anything environment-agnostic; only add files under `envs/<env>/` (plus a `patches:` entry) for values that genuinely differ per environment (LB IP, replica count, resource limits, etc.) — don't duplicate whole manifests. Never hardcode a real domain in `base/`; use `example.com` and let the `replace-domain`/`prefix-domain` components handle it.
- **Field/list ordering in YAML files** (including `kustomization.yaml`, Flux `Kustomization`/`HelmRelease`, and any other k8s manifest) — see `.agents/instructions/sorting.md`.
- **Branch naming and the issue-first prerequisite for any new branch** — see `.agents/instructions/branching.md`.
- **Environment identifiers** are one of `dbg`, `dev`, `head`, `poc`, `prod`, `qa`, `rebuild`, `src` — used consistently across `terragrunt/`, `k8s/*/envs/`, and `k8s/components/envs/`. See [`docs/architecture/environments.md`](docs/architecture/environments.md) for what each one is for.
- **Flux `Kustomization.spec.dependsOn`**: only add it for ordering between two Flux-reconciled units (e.g. `onepassword-connect`'s `flux/ks.yaml` depends on `external-secrets`). Never add a `dependsOn` on something 
   - installed via the bootstrap `helmfile` (e.g., cilium, sealed-secrets, cert-manager, external-secrets, onepassword-connect, flux-operator/instance — see `k8s/bootstrap/helmfile/apps/helmfile.yaml.gotmpl`) or
   - whose CRDs are installed via the bootstrap `helmfile` (e.g., grafana-operator, kube-prometheus-stack — see `k8s/bootstrap/helmfile/crds/helmfile.yaml.gotmpl`)
   
   those are already installed and healthy before Flux starts reconciling anything, so the ordering is guaranteed by the bootstrap sequence, not by Flux.

- **Commit messages** follow the shared Conventional Commits convention (see imported commons file above), enforced/generated here by Renovate config in `.github/renovate/organize-semantic-scope.json5` (but keep doing this by hand too): scope is typically `<env-or-base>/<app>` for kustomize overlays/bases, or `<env>/<module>` for terragrunt, e.g. `chore(base/external-secrets): ...`; omit the `base`/`<env>` prefix (just `<app>`) when a change touches `base/` and one or more `envs/` at once, since it isn't specific to either.
- Renovate manages dependency updates (`.github/renovate.json5` + `.github/renovate/*.json5`); PR labeling is automated from changed paths (`.github/labeler.yml`) and merges via Mergify (`.github/mergify.yml`) — don't hand-roll equivalents.

## PR discipline

- Even a throwaway commit meant to be reverted minutes later belongs on a feature branch, never `main` — see the `track-branch` skill's `tmp(<env>): ...` convention (under Commands above) for a concrete example of a temporary, self-reverting change still living entirely on its own branch. That feature branch is named `issue/<issue-number>_<shorttext>` — see `.agents/instructions/branching.md` for the naming convention and the issue-first prerequisite it depends on.
- **No feature/bugfix PR merges without a related issue** (Renovate's own dependency-update PRs excepted) — see `.agents/instructions/branching.md` for what counts as a valid reference (`Closes`/`Relates to`) and the pre-merge check that the referenced issue(s) actually exist.
- **No CI in this repo.** There's no GitHub Actions/CI pipeline gating PRs (see "Commands" above — validation is `pre-commit`, `kustomize build`/`helmfile template`, and Flux's own reconciliation, none of which run as PR checks). Don't offer to watch/subscribe to a PR for CI status, don't treat "waiting on CI" as a reason to hold off, and don't apply any CI-red/re-run workflow to this repo's own PRs — there's nothing to watch. A PR here is ready once it's mergeable and any human review is addressed.
- **Post-merge follow-ups**: put anything to address *after* merge (not blocking merge) under a `## Post-merge follow-ups` heading in the PR body, as a checklist — kept separate from `## Before merging` above. Don't pre-create a tracking issue for this speculatively before the PR exists or merges (that caused duplicate/stale issues in the past, e.g. #1117 vs #1118). Instead, once the PR merges, automation reads that heading and opens exactly one tracking issue labeled `post-merge-followup`, linked back to the PR; a separate daily digest emails every open issue carrying that label until it's closed. That label is reserved for this automation — never apply it by hand to a regular issue, so it stays a small, clean queue distinct from the normal issue backlog/project board. Most PRs won't need this section at all.
- **Test plan**: PRs opened by an agent include a `## Test Plan` checklist in the body — tests identified while making the change, plus any the user adds during the conversation — and every item gets ticked off (by actually running/verifying it, not just checking the box) before the PR is called mergeable. This is separate from Renovate's own major-update PRs, which get a generic version of this checklist automatically via `.github/renovate/major-test-plan.json5` (`prBodyNotes` on `matchUpdateTypes: ["major"]`) since Renovate authors its own PR body and never inherits a repo `.github/pull_request_template.md`; patch/minor Renovate PRs are left alone.
