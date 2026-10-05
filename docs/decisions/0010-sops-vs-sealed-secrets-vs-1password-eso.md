# SOPS vs. sealed-secrets vs. 1Password + External Secrets Operator

## Status

current

## Context

Secrets never live in Git in plaintext, but no single mechanism covers the whole lifecycle: some secrets have to exist *before* a Kubernetes cluster or Flux exists at all (Proxmox API tokens, remote-state encryption), while everything else is reconciled by a running cluster from Git. sealed-secrets was present from nearly the start (2024-12-27); 1Password + External Secrets Operator (ESO) was added much later (2026-09-04) once a need arose for a secret whose source of truth should live outside Git entirely rather than be committed as ciphertext — see [`secrets.md`](../architecture/secrets.md) for the full current-state mechanism.

## Options considered

- **One mechanism for everything (rejected)** — SOPS alone can't be read by a running cluster's controllers without a decrypted copy somewhere; sealed-secrets alone can't serve the pre-cluster Terragrunt stage (no controller exists yet to decrypt anything); ESO alone would mean every secret's source of truth lives in 1Password with nothing committed, even for the simple, app-owned, rarely-rotated case where committed ciphertext reviewable in a diff is preferable.
- **Split by when the secret is needed and where its source of truth should live (chosen).**

## Decision

Three mechanisms, split mechanically rather than stylistically (see [`secrets.md`](../architecture/secrets.md) for the live wiring):

- **SOPS** (age-encrypted, file-based) — anything Terragrunt/OpenTofu needs before a cluster exists to run a controller for it.
- **sealed-secrets** — an app-owned secret that should be versioned and reviewable alongside the manifests that use it, where re-sealing on a cluster rebuild is an acceptable cost.
- **1Password + ESO** — a secret whose source of truth should live outside Git entirely: centrally rotated, shared with things outside the cluster, or just preferred over re-sealing per app.

A one-time `op inject` bridge connects the SOPS/pre-cluster stage to the in-cluster stage, seeding 1Password Connect's own bootstrap credentials before ESO can take over.

## Consequences

- Three mechanisms to understand instead of one, each with its own recovery story — sealed-secrets' sealing key has no automated backup today (known gap, [issue #130](https://github.com/isejalabs/homelab/issues/130)); a secret's correct mechanism depends on *when* it's needed, which isn't always obvious to a newcomer.
- No secret of any kind sits in Git as plaintext at any stage, including the bootstrap bridge (`s3cr3t.yaml` carries only `op://` references, never resolved material).
- Moving a secret from one mechanism to another later (e.g. an app-owned sealed-secret graduating to 1Password-sourced) is a manual migration, not something either tool handles automatically.
