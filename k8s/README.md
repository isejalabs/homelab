See [`docs/architecture/workloads.md`](../docs/architecture/workloads.md) for a full catalog of every app and infra component actually deployed — what each one is, and how it's installed.

## Folder Structure

```
📁 k8s
├── 📁 apps                     # application workloads, grouped by domain
│   ├── 📁 diag                   # e.g. whoami
│   ├── 📁 dns                    # e.g. adguard, unbound
│   ├── 📁 finances                # e.g. actualbudget
│   ├── 📁 home-automation         # e.g. zigbee2mqtt
│   ├── 📁 identity                # e.g. keycloak
│   ├── 📁 monitoring              # e.g. checkmk-agent, metrics-server
│   └── 📁 network                # e.g. unifi-controller
├── 📁 bootstrap                # second bootstrap phase: helmfile + Flux hand-off (see bootstrap/README.md)
│   ├── 📁 cluster/flux           # Flux `sets/` (infra|apps × minimal|optional, plus minimal and soaking), composed per env under flux/envs/<env>
│   ├── 📁 helmfile               # helmfile definitions: crds/, apps/, base/, templates/*.gotmpl
│   └── 📁 kustomize/personal     # personal credentials injected via `op inject` during bootstrap
├── 📁 components               # shared DRY kustomize layer (see components/README.md)
│   ├── 📁 envs                   # per-environment Components included by every app/infra overlay
│   └── 📁 transformers           # transformers those components apply (replace-path, replace-domain, prefix-domain, add-labels, set-flux-defaults)
├── 📁 infra                    # infrastructure workloads, grouped by namespace
│   ├── 📁 cert-manager
│   ├── 📁 cnpg-system
│   ├── 📁 common/ns              # aggregates every group's `_ns` base into one Flux Kustomization ("infra-ns")
│   ├── 📁 csi-proxmox
│   ├── 📁 external-dns
│   ├── 📁 external-secrets
│   ├── 📁 flux-system
│   ├── 📁 gateway-api
│   ├── 📁 keycloak
│   ├── 📁 kopiur-system
│   ├── 📁 kube-system
│   ├── 📁 longhorn-system
│   ├── 📁 o11y
│   └── 📁 sealed-secrets
└── 📁 test                     # throwaway manifests for manually exercising things (e.g. storage classes); not reconciled by Flux
```

### Shape of an app/infra unit

Every leaf under `apps/<domain>/<app>` and `infra/<namespace>/<component>` follows the same three-folder shape (with one exception, `_ns`, below):

```
📁 <app-or-component>
├── 📁 base          # environment-agnostic manifests + kustomization.yaml (placeholder domain example.com)
├── 📁 envs/<env>    # per-environment overlay: includes ../../../../../components/envs/<env> and patches only what differs
└── 📁 flux          # the Flux Kustomization (ks.yaml) reconciling this unit, plus its own kustomization.yaml
```

`flux/ks.yaml`'s `spec.path` is written pointing at `base/` but gets rewritten to `envs/<env>/` per environment by the `replace-path` transformer (see `components/README.md`).

A `_ns` folder (e.g. `infra/cert-manager/_ns`) is the exception: it only has a `base/` with the namespace manifest, no `envs/`/`flux/` of its own. Every group's `_ns/base` is pulled in as a resource by `infra/common/ns`, which is the one Flux Kustomization (`infra-ns`) that actually creates all infra namespaces.

### README of an app/infra unit

Every unit has a `README.md` next to its `base/` (so GitHub shows it when the folder link in [`workloads.md`](../docs/architecture/workloads.md) is opened). It is the front door for one workload: what it is, where to reach it, what to run. It does not repeat what a cross-cutting doc owns; it links there (see [Central or in the README](#central-or-in-the-readme)). Tracked in [#2098](https://github.com/isejalabs/homelab/issues/2098).

Headings are fixed and enforced: [`scripts/check-unit-readmes.sh`](../scripts/check-unit-readmes.sh) (run by the `docs-link-check` workflow) fails for a unit without a README, without one of the eight `##` headings below, with the headings out of order, without the four rows of the `At a glance` table, with a URL in a code span in `Access`, or whose README is not listed in the docs navigation. Three of the rows are also checked against the manifests, see [Facts checked against the manifests](#facts-checked-against-the-manifests). Change the template and the script's two lists together. A section that does not apply says so in one line (`Not exposed.`) instead of being dropped. A new unit's README also gets an entry under `Components and apps` in [`.ci/mkdocs/mkdocs.yml`](../.ci/mkdocs/mkdocs.yml), otherwise the docs site builds the page but does not show it in the sidebar, and the check fails. Extra sections (`Secrets and storage`, `Known quirks`, install notes) go after `Cheat sheet`.

````markdown
# <name>

One sentence: what it is and what the cluster uses it for.

## At a glance

| | |
| --- | --- |
| Namespace | `<namespace>` |
| Runs in | `<env>`, `<env>` (Flux set `<set>`) |
| Installed via | HelmRelease `<chart>` / raw manifests / operator custom resources / vendored release |
| Flux Kustomization | `<name>`, depends on `<a>`, `<b>` |

## Purpose

What problem it solves here and why this product (link the ADR if there is one). 2-5 sentences.

## Where it is used

- **Used by**: the workloads and environments that rely on it (databases, resolvers, operators, gateways).
- **Depends on**: what it needs at runtime, beyond the Flux `dependsOn`.

## Access

| env | URL or address | Notes |
| --- | --- | --- |
| `dev` | `https://dev-<sub>.dev.iseja.net` | |
| `prod` | `https://<sub>.prod.iseja.net` | |

Only environments that run it. Write every URL as a Markdown link (`[https://dev-<sub>.dev.iseja.net](https://dev-<sub>.dev.iseja.net)`), never as a code span, so it can be clicked; addresses and ports without a scheme stay code. State the subdomain when it differs from the folder name, the gateway it is attached to, and where the login lives (1Password item, no values). The general hostname scheme is in [`reference/environments.md`](../docs/reference/environments.md#domain-and-naming). Not exposed units say `Not exposed.` and name the in-cluster Service.

## Updates

Where each version is pinned (file and field), and only what deviates from the default flow in [`update-handling.md`](../docs/operations/update-handling.md): pinned minor, manual merge, staged in `prod`, vendored release.

## Operations

Links to the runbooks (backup and restore, break-glass, troubleshooting) that already exist in `docs/`. No procedure is copied here.

## Cheat sheet

Commands that were useful for this unit, with the `--context admin@<env>-homelab` form.

## Upstream

Homepage, documentation, source repository, chart or release feed.
````

#### Central or in the README

| Information | Where | Why |
| --- | --- | --- |
| Hostname scheme (`<env>-<sub>.<env>.iseja.net`, `prod` without prefix) | [`reference/environments.md`](../docs/reference/environments.md#domain-and-naming) only | Uniform across apps; a README names its own subdomain and any exception |
| Renovate, automerge and staged-rollout rules | [`update-handling.md`](../docs/operations/update-handling.md) only | One rule set for all units; a README says which file holds the pin and links the row |
| What each environment is for, which apps run where | [`environments.md`](../docs/architecture/environments.md) and [`workloads.md`](../docs/architecture/workloads.md) | A README only lists the environments that run its unit |
| Backup, restore, break-glass and troubleshooting procedures | `docs/backup/`, `docs/identity/`, `docs/troubleshooting/` | Procedures span several units; a README links them |
| Why a product was chosen | [`docs/decisions/`](../docs/decisions) | An ADR is not rewritten; a README links it |
| Purpose, consumers, access, pins, commands, quirks of one unit | The unit's README | Changes with the unit and is updated in the same PR |

#### Facts checked against the manifests

The READMEs are hand-written and CI keeps three rows of `At a glance` honest ([#2111](https://github.com/isejalabs/homelab/issues/2111)); generating them was rejected, because a generated block goes stale with every Renovate bump. [`scripts/check-unit-readmes.sh`](../scripts/check-unit-readmes.sh) compares each row with the manifest that owns the fact, so a cell must follow this grammar and put any prose elsewhere (`Purpose`, `Where it is used`, `Updates`):

| Row | Grammar | Compared with |
| --- | --- | --- |
| `Namespace` | the first code span is the namespace; prose may follow (`` `unifi` (created by ...) ``). A unit without one starts with `none` (only [`common/ns`](infra/common/ns/README.md)) | `namespace:` in `base/kustomization.yaml` |
| `Flux Kustomization` | `` `<name>`, depends on `<a>`, `<b>` `` or `` `<name>`, no `dependsOn` `` and nothing else; the order of the names does not matter | `metadata.name` and `spec.dependsOn[].name` of the first `Kustomization` in `flux/ks.yaml`. The name differs from the folder for `gateway` (`gateway-api`), `kubelet-serving-cert-approver` (`k-serving-cert-approver`) and `checkmk-agent` (`checkmk-kube-agent`) |
| `Runs in` | `all N environments` or a comma-separated list of environment code spans, then `` (Flux set `<set>`) `` or `(no Flux set, registered in ...)`, then optionally `; free prose` (bootstrap remarks, exceptions). Only the part before the first `;` is parsed, so keep a `;` out of the parentheses | the environments whose `flux/envs/<env>/kustomization.yaml` reach the unit, directly or through the sets (so `zigbee2mqtt`, registered in `prod` only, is `prod`), and the set in `flux/sets/` that lists the unit |

The check reads the files, not a rendered overlay, so it runs in the `docs-link-check` workflow with plain `sh` and `awk`. Which Flux set and which environments a unit has is derived with the same helpers as [`scripts/check-workloads-catalog.sh`](../scripts/check-workloads-catalog.sh) ([`scripts/lib/flux-sets.sh`](../scripts/lib/flux-sets.sh)).

## Kustomize overlay approach

See [`docs/architecture/kustomize.md`](../docs/architecture/kustomize.md) for how the `base`/`envs/<env>`/`flux` overlay triad, overlay patches, the shared `components` layer, and its `replacements`-based transformers (domain rewriting, common labels, Flux `spec.path`/`spec.interval` rewriting) fit together.
