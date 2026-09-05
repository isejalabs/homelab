# Agent Instructions

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

Terragrunt (run from `terragrunt/<non-prod|prod>/<account>/<region>/<env>/<module>`):

```sh
cd terragrunt/non-prod/eu-central-1/dev/vehagn-k8s
terragrunt plan
terragrunt apply
```

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
- **Environment identifiers** are one of `dbg`, `dev`, `head`, `poc`, `prod`, `qa`, `rebuild`, `src` — used consistently across `terragrunt/`, `k8s/*/envs/`, and `k8s/components/envs/`.
- **Flux `Kustomization.spec.dependsOn`**: only add it for ordering between two Flux-reconciled units (e.g. `onepassword-connect`'s `flux/ks.yaml` depends on `external-secrets`). Never add a `dependsOn` on something 
   - installed via the bootstrap `helmfile` (e.g., cilium, sealed-secrets, cert-manager, external-secrets, onepassword-connect, flux-operator/instance — see `k8s/bootstrap/helmfile/apps/helmfile.yaml.gotmpl`) or
   - whose CRDs are installed via the bootstrap `helmfile` (e.g., grafana-operator, kube-prometheus-stack — see `k8s/bootstrap/helmfile/crds/helmfile.yaml.gotmpl`)
   
   those are already installed and healthy before Flux starts reconciling anything, so the ordering is guaranteed by the bootstrap sequence, not by Flux.

- **Commit messages** follow Conventional Commits with a path-derived scope (enforced/generated by Renovate config in `.github/renovate/organize-semantic-scope.json5`, but keep doing this by hand too): `type(scope): subject`, e.g. `chore(base/external-secrets): ...`, `feat: ...`. Scope is typically `<env-or-base>/<app>` for kustomize overlays/bases, or `<env>/<module>` for terragrunt; omit the `base`/`<env>` prefix (just `<app>`) when a change touches `base/` and one or more `envs/` at once, since it isn't specific to either. Don't reference an issue in the commit message itself (no `Refs #123`/`Closes #123`) — issue references (with a closing keyword where appropriate) belong in the PR description, not individual commits.
- Renovate manages dependency updates (`.github/renovate.json5` + `.github/renovate/*.json5`); PR labeling is automated from changed paths (`.github/labeler.yml`) and merges via Mergify (`.github/mergify.yml`) — don't hand-roll equivalents.
