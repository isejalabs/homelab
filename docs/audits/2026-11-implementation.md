---
date: 2026-11-16
status: Assessment complete; one follow-up issue per finding created beneath https://github.com/isejalabs/homelab/issues/2345 (see Findings), none of them decided yet
scope: the whole implementation as found in the repository at commit 99bcbcfb — technical stack, Terragrunt layer, bootstrap, Flux and kustomize multi-environment design, update management, secrets, workload hardening, backup and recovery, observability, CI, repository structure and documentation. Not covered — any live cluster or host (nothing was queried), the out-of-repo components (Salt, Checkmk sites, gateways), the Terraform modules in their own repositories, and the content of individual runbooks (not re-tested)
origin: Claude (Claude Code, model Fable 5.2), read-only review of the checkout; counts were taken with grep and find over the tracked files
tracking: https://github.com/isejalabs/homelab/issues/2345
---

# Implementation assessment — November 2026

## Summary

The implementation is well engineered and clearly above typical home-ops practice in bootstrap design, CI, supply-chain pinning and in stating what is and is not recoverable. Its main weakness is proportion: a lot of platform, process and text for a small payload, and three mechanisms whose cost grows with every unit that is added (the positional domain replacement, the per-environment overlay boilerplate and the copied Terragrunt blocks).

Runtime behaviour is inferred from the manifests. A count in this document says what is written in the repository, not what a cluster does; chart defaults may add to it.

## Scorecard

| Area | Rating | In one line |
| --- | --- | --- |
| Stack choice (Proxmox, Talos, Cilium, Flux) | Strong | Coherent and mainstream, with ADRs that record the rejected options |
| Bootstrap | Strong | The helmfile reads chart, version and values from the Flux manifests, so there is one version source |
| Terragrunt layer | Good | Encrypted state, per-environment roles, placeholders that keep CI free of keys; heavy copy-paste |
| Multi-environment (kustomize) | Mixed | Works and is covered by CI; the domain mechanism is brittle and most overlays are boilerplate |
| Update management | Good | Fine-grained Renovate rules; `qa` before `prod` only holds for a few units |
| Secrets | Good | Clean split by stage; three mechanisms where two would do |
| Workload hardening | Weak | Few limits, policies, disruption budgets or restricted namespaces |
| Backup and recovery | Good | A rebuild environment and restore drills; the known gaps are documented |
| Observability | Mixed | Checkmk outside the clusters is sound; nothing reports a failed reconciliation |
| CI | Strong | 13 workflows on pull requests, a bootstrap test on a throwaway cluster, actions pinned by commit |
| Documentation | Good, oversized | Structure and honesty are excellent; about 198,000 words |

## What is strong

- **One version source for bootstrap.** [`release-templates.yaml`](../../k8s/bootstrap/helmfile/base/release-templates.yaml) and [`ocirelease.yaml.gotmpl`](../../k8s/bootstrap/helmfile/templates/ocirelease.yaml.gotmpl) derive each helmfile release from the unit's `OCIRepository` and `HelmRelease`, so the bootstrap cannot install a different version than Flux reconciles afterwards.
- **CRDs before Flux.** Installing CRDs in the bootstrap removes most `dependsOn` chains, and the apps stage is tested in CI against a throwaway kind cluster.
- **Supply chain.** 14 charts come from an `OCIRepository`, GitHub Actions are pinned by commit, tools by `mise.lock` with provenance verification, and upstream manifests are vendored instead of fetched by Flux.
- **State handling.** OpenTofu state encryption, S3 native locking, a state role per environment, and placeholder secrets so that `validate` runs in CI without a key.
- **Topology.** Every environment has three control-plane nodes on three Proxmox hosts, and the leader-election tuning states its cost next to its benefit.
- **Flux sets.** `minimal`, `optional` and `standing` say clearly which environment runs what.
- **Monitoring outside the clusters,** so a broken cluster can still be seen.
- **Disclosure guard.** Pattern checks in pre-commit plus a private term list kept outside the repository.

## Findings

Ordered by importance. Each finding has its own issue with the options; this document only states the observation.

### F1 — Domain replacement by position is brittle

The [`replace-domain`](../../k8s/components/transformers/replace-domain/kustomization.yaml) component has ten replacement files that swap dot-separated segments of a hostname by index, one file per kind or per app. They depend on the order of two replacements (the base value itself contains a dot), need `reject` entries for objects without a hostname, and `DNS_ZONE` repeats `DOMAIN_BASE` plus `DOMAIN_TLD` by hand because one target cannot use the split. Every new kind that carries a hostname needs a new file. Flux `postBuild.substitute` is already used for the storage variables and would cover the domain as a plain string. Revising this amends [ADR 0004](../decisions/0004-kustomize-overlays.md). Tracked in [#2346](https://github.com/isejalabs/homelab/issues/2346).

### F2 — Most environment overlays are boilerplate

There are 256 overlay `kustomization.yaml` files for 32 units, and 169 of 259 environment directories contain nothing else: they include the environment component and `../../base`. A new unit starts with eight such files. Tracked in [#2347](https://github.com/isejalabs/homelab/issues/2347).

### F3 — Terragrunt repeats itself

The block that decrypts and merges the five SOPS files is copied into 12 files under `terragrunt/_envcommon/` in addition to [`root.hcl`](../../terragrunt/root.hcl). Each cluster unit spells out about 100 lines of nodes whose address and VM ID follow a pattern. Tracked in [#2348](https://github.com/isejalabs/homelab/issues/2348).

### F4 — `qa` does not precede `prod` for most updates

All environments reconcile `main`. Digest and patch updates are automerged by Renovate and minor ones by Mergify, and a `minimumReleaseAge` exists only for the staged units. For every other unit an update reaches `prod` together with `qa`, possibly within hours of the release. The environments protect infrastructure-level and Terragrunt changes well, but not most application updates. Tracked in [#2349](https://github.com/isejalabs/homelab/issues/2349).

### F5 — Workload hardening is thin

- Pod Security admission: three namespaces are labelled `privileged` and one `restricted`, out of 21 `Namespace` objects.
- One own network policy; the model is open in [#1995](https://github.com/isejalabs/homelab/issues/1995).
- One `PodDisruptionBudget`, no topology spread, no priority class.
- Resource limits in 16 files.
- No `HelmRelease` sets `driftDetection`.

Tracked in [#2350](https://github.com/isejalabs/homelab/issues/2350).

### F6 — One component is pinned twice and has drifted

The Talos `extra_manifests` of all eight cluster units fetch kubelet-serving-cert-approver v0.11.0 from a remote URL, without a Renovate annotation, while Flux uses the vendored v0.12.1. A cluster bootstrap therefore depends on that host being reachable, which the rule against remote resources ([#2055](https://github.com/isejalabs/homelab/issues/2055)) excludes for Flux only. Tracked in [#2351](https://github.com/isejalabs/homelab/issues/2351).

### F7 — sealed-secrets serves three objects

The repository has 3 `SealedSecret` objects against 20 `ExternalSecret` objects. For those three there is a controller, a bootstrap release that others wait for, and a sealing key that has to survive a rebuild. The larger risks in this area are already known: the missing backup of the 1Password-held secrets ([#1636](https://github.com/isejalabs/homelab/issues/1636)) and the single age recipient. Tracked in [#2352](https://github.com/isejalabs/homelab/issues/2352).

### F8 — Nothing reports a failed reconciliation

The Flux instance runs the notification-controller, but there is no `Alert`, `Provider` or `Receiver`. Separately, the `o11y` units install CRDs for a stack that does not run and still produce Renovate updates. Tracked in [#2353](https://github.com/isejalabs/homelab/issues/2353).

### F9 — Agent instructions have drifted from the code

`AGENTS.md` cites `k8s/bootstrap/helmfile/crds/helmfile.yaml.gotmpl` (the file is `helmfile.yaml`), says eleven validation workflows run on pull requests (13 do, not counting `labeler`) and omits two transformers. The file grows by one rule per incident; a rule that became a check, such as the one on `targetNamespace`, ages better. Tracked in [#2354](https://github.com/isejalabs/homelab/issues/2354).

### F10 — Proportion, and the volume and voice of the documentation

Eight environments, 32 units and nine applications are backed by about 198,000 words and 617 commits since September 2026, of which 194 are `docs` and 236 `chore`. That pace depends on AI assistance, which raises the question of which parts could still be maintained without it.

The documentation's structure is its best part: a rule for where a doc belongs, status front matter, ADRs, and checks for links, diagrams, navigation and unit READMEs. The disaster-recovery guide's separation of what was exercised from what the owner reports is rare and valuable. The problems are volume and voice:

- Several runbooks have 5,000 to 8,000 words.
- Much prose, and many YAML and HCL comments, read as a change log: nested parentheses, "confirmed live", issue numbers inline. The reader needs the rule; the history belongs in the ADR, the issue or the PR.
- `docs/audits/` also holds the results of single work phases, and `-claude` variants next to the original files.

Tracked in [#2355](https://github.com/isejalabs/homelab/issues/2355).

## Suggested order

F4, F6 and F8 are small and reduce real risk. F1 pays off most over time and needs a new ADR, because it revises ADR 0004. F2 and F3 are refactorings without a deadline. F5 is best started as a baseline definition, with the network-policy model staying in [#1995](https://github.com/isejalabs/homelab/issues/1995).

## Method and limits

- The checkout was read; no cluster, host or monitoring site was queried.
- Counts come from pattern searches over `k8s/apps` and `k8s/infra` (vendored files excluded where stated in the issue). A search for probe settings was not reliable and is not reported.
- The Terraform modules, the Salt states and the Checkmk site configuration live outside this repository and were not assessed.
- Ratings are a judgement, not a measurement.
