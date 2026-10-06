# SOPS vs. sealed-secrets vs. 1Password + External Secrets Operator

## Status

current

## Context

Secrets never live in Git in plaintext, but no single mechanism covers the whole lifecycle: some secrets have to exist *before* a Kubernetes cluster or Flux exists at all (Proxmox API tokens, remote-state encryption), while everything else is reconciled by a running cluster from Git. sealed-secrets came with [@vehagn](https://github.com/vehagn/homelab)'s reference repo (see [ADR 0001](0001-proxmox-and-talos.md)) — inherited, not independently evaluated at first — and was used for cluster-relevant secrets from nearly the start (2024-12-27). 1Password + External Secrets Operator (ESO) was added much later (2026-09-04), once operating sealed-secrets long enough revealed real friction.

sealed-secrets' sealing key is Terraform-managed (`terraform/README.md`'s `module.sealed_secrets.kubernetes_secret.sealed-secrets-key`), pre-defined up front via an `openssl`-generated master key rather than left to the controller's own default (auto-generated, periodically rotating) key. That rotation is still the controller's default behavior even with a pre-defined master key, so creating a *new* sealed secret later could mean needing the specific "offline" key a given secret was originally sealed against, not whatever key happens to be currently active. On top of that, creating or rotating a sealed secret was a manual, repeated process: copy the `kubeseal` command from documentation, strip the placeholder credential it shows, substitute the real value, run it, re-apply — the same manual dance every time, for every environment. That cost is exactly why a distinct sealed secret per environment was often skipped where it could be, rather than generated faithfully for every case that would "ideally" want one.

1Password + ESO removes that recreation burden entirely: a credential is stored once in 1Password, referenced by one static path in the `ExternalSecret` definition, and a credential rotation in 1Password alone is enough — no re-sealing, no re-running a command, no touching the cluster at all.

## Options considered

- **One mechanism for everything (rejected)** — SOPS alone can't be read by a running cluster's controllers without a decrypted copy somewhere; sealed-secrets alone can't serve the pre-cluster Terragrunt stage (no controller exists yet to decrypt anything); ESO alone would mean every secret's source of truth lives in 1Password with nothing committed, even where that's unnecessary overhead.
- **Split by when the secret is needed and where its source of truth should live (chosen, refined by operational experience)** — the original split (sealed-secrets for an app-owned, Git-reviewable secret; ESO for one whose source of truth lives outside Git) still describes what's committed today, but lived experience with sealed-secrets' rotation/recreation cost has shifted the practical default toward ESO even for cases that would nominally fit sealed-secrets' niche.

## Decision

Three mechanisms, split mechanically by *when* a secret is needed (see [`secrets.md`](../architecture/secrets.md) for the live wiring):

- **SOPS** (age-encrypted, file-based) — anything Terragrunt/OpenTofu needs before a cluster exists to run a controller for it.
- **sealed-secrets** — existing cluster-relevant secrets created this way stay as-is; not being actively replaced wholesale.
- **1Password + ESO** — the default for every *new* secret going forward, regardless of whether it would also fit sealed-secrets' original niche, specifically to avoid the re-sealing/recreation operational cost described above.

A one-time `op inject` bridge connects the SOPS/pre-cluster stage to the in-cluster stage, seeding 1Password Connect's own bootstrap credentials before ESO can take over.

## Consequences

- Three mechanisms to understand instead of one, each with its own recovery story — sealed-secrets' sealing key has no automated backup today (known gap, [issue #130](https://github.com/isejalabs/homelab/issues/130)); a secret's correct mechanism depends on *when* it's needed and, now, on a practical preference learned from experience rather than the mechanical split alone.
- No secret of any kind sits in Git as plaintext at any stage, including the bootstrap bridge (`s3cr3t.yaml` carries only `op://` references, never resolved material).
- Existing sealed-secrets usage isn't being migrated proactively — the operational lesson changes the default for *new* secrets, not a mandate to rewrite what's already committed.
