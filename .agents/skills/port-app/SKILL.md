---
name: port-app
description: Port a Kubernetes app/component from a Flux2 "cluster-template"-style homelab repo (default source: onedr0p/home-ops) into this repo's k8s/infra or k8s/apps conventions — base/envs/flux layout, namespace registration, and flux-set registration.
---

# Port an app from another homelab repo

Transforms manifests from a source repo that follows the common onedr0p/cluster-template Flux2
layout (`kubernetes/apps/<namespace>/<component>/app/*.yaml` + `ks.yaml`) into this repo's layout
(`k8s/infra/<namespace>/<component>/{base,envs,flux}` or `k8s/apps/<category>/<component>/{base,envs,flux}`).

Ground-truth examples already in this repo's history — re-read these with `git show <sha>` if you
need to see real diffs, don't guess:
- `3be1689119a5c82bdbe69402aa171cc83e50b344` — `external-secrets` + `onepassword-connect` (two
  components sharing one namespace; the canonical simple case).
- `7a47dfc708b749e41c1ae68efd1ebdc0da1fd50d` — `flux-instance` + `flux-operator` (large migration
  commit, noisy; only useful for those two components' final shape, which now also lives at
  `k8s/infra/flux-system/flux-instance` and `k8s/infra/flux-system/flux-operator` — prefer reading
  those live files over the old commit, the commit predates some convention changes).

## 0. Resolve inputs

Ask (or infer from the request) before starting:
1. **Source**: `owner/repo` (default `onedr0p/home-ops`) + path under `kubernetes/apps/<namespace>/<component>`.
2. **Destination area**: `k8s/infra/<namespace>/<component>` (cluster infrastructure/controllers) or
   `k8s/apps/<category>/<component>` (end-user workloads). If ambiguous, ask — infra namespaces are
   registered centrally (step 4), apps are self-contained (step 5).
3. **Destination namespace/category and component name** — default to the source names unless told
   otherwise.
4. **Flux set**: `minimal` or `optional` (`k8s/bootstrap/cluster/flux/sets/{infra,apps}/{minimal,optional}/`).
   Infra components generally go in `minimal` (they're small/cheap and useful even in throwaway envs
   like `dbg`); ask if unsure for apps.

Fetch the source tree without needing `gh auth` (this environment's `gh` may lack credentials):
```sh
curl -s "https://api.github.com/repos/<owner>/<repo>/git/trees/main?recursive=1" \
  | python3 -c "import json,sys; [print(t['path']) for t in json.load(sys.stdin)['tree'] if t['path'].startswith('kubernetes/apps/<namespace>/<component>')]"
```
Fetch individual files with `curl -s https://raw.githubusercontent.com/<owner>/<repo>/main/<path>`.

## 1. Detect multi-component sources ("app" + extra subfolders)

List the immediate subfolders of the source component directory. The subfolder named `app` is the
primary component. **Any other subfolder becomes its own sibling destination component**, named
`<component>-<subfolder>`, with its own full base/envs/flux triad (step 3), registered separately in
the flux set (step 6), and normally `dependsOn` the primary component's flux Kustomization name.

Real example — `kopiur-system/kopiur` has `app/` and `repository/`. Source `kopiur/ks.yaml` is a
multi-document YAML with two `Kustomization` objects (`kopiur` → `.../kopiur/app`, `kopiur-repository`
→ `.../kopiur/repository`, the second `dependsOn: [{name: kopiur}]`). In this repo that becomes two
**separate** directories, each with its own `flux/ks.yaml` (this repo never uses multi-document
`ks.yaml` files — one Flux Kustomization per component directory):
- `k8s/infra/kopiur-system/kopiur/` (from `app/`)
- `k8s/infra/kopiur-system/kopiur-repository/` (from `repository/`, `dependsOn: kopiur`)

If the source component has no subfolders other than `app`, there's just one destination component.

## 2. What to carry over vs. drop

Copy every manifest file from `app/` (or the extra subfolder) as-is **except**:
- `kustomization.yaml` — always rewritten, see step 3.
- Any file whose only purpose is wiring into a source-repo-only shared component (e.g. a
  `GrafanaDashboard`/`PrometheusRule`/`PodMonitor`/`Receiver`/`ExternalSecret` that exists solely to
  feed the source repo's own `components/alerts`, `components/gatus`, etc., which don't exist here).
  **Flag these to the user instead of silently dropping them** — list what you excluded and why, so
  they can decide whether an equivalent belongs in this repo.
- Real domains in `HTTPRoute`/`Ingress`/`Certificate`/`Gateway` hostnames — replace with `example.com`
  (this repo's `replace-domain`/`prefix-domain` components inject the real domain per environment;
  never commit a real hostname into `base/`).

The source's own `kustomization.yaml` at `kubernetes/apps/<namespace>/` (the one that aggregates
`namespace.yaml` + every component's `ks.yaml`, often pulling in shared `components:`) has **no
destination equivalent as a single file** — its two jobs are split apart in steps 4 and 6.

Keep chart version pins (tag, or tag+digest) exactly as sourced — Renovate updates them afterward.
Keep `# yaml-language-server: $schema=...` comment lines verbatim; this repo has converged on the
same `https://k8s-schemas.home-operations.com/...` schema catalog onedr0p uses (newer ported files
use it; a few older pre-existing files still reference `kubernetes-schemas.pages.dev` — don't "fix"
those while porting an unrelated component).

## 3. Generate the component directory

For each destination component (`k8s/<infra|apps>/<namespace-or-category>/<component>/`):

**`base/kustomization.yaml`** — copy source `app/kustomization.yaml` resources list, but:
- add an explicit `namespace: <namespace>` field (the source relies on its parent aggregator
  kustomization for this; this repo doesn't have one per-namespace, so every component's `base/`
  must set it itself).
- strip the `./` prefix from resource entries (`./helmrelease.yaml` → `helmrelease.yaml`).
- keep the `# yaml-language-server: $schema=https://json.schemastore.org/kustomization` header.

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: <namespace>

resources:
  - <file1>.yaml
  - <file2>.yaml
```

**`envs/<env>/kustomization.yaml`** for all 8 envs (`dbg dev head poc prod qa rebuild src`) — identical
boilerplate, no `namespace:` field (inherited from base), no patches unless you have a concrete,
requested per-env difference (LB IP, replica count, resource limits — see other apps under
`k8s/infra/*/envs/*` or `k8s/apps/*/envs/*` for patch examples):

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

components:
  - ../../../../../components/envs/<env>

resources:
  - ../../base
```

**`flux/kustomization.yaml`** — always identical:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ks.yaml
```

**`flux/ks.yaml`** — derive from the source's `ks.yaml` entry for this subfolder:
- `metadata.name` = the destination component's directory name (e.g. `kopiur-repository`, not `kopiur`).
- `spec.path` = `./k8s/<infra|apps>/<namespace-or-category>/<component>/base` — **always ends in
  `/base`**, never `/envs/<env>`. The per-environment path rewrite happens automatically later via the
  `replace-path` kustomize component when `k8s/bootstrap/cluster/flux/envs/<env>/kustomization.yaml`
  is built — do not hand-write an env-specific path here.
- keep `interval`, `prune`, `wait`, `sourceRef` (always `GitRepository flux-system/flux-system`),
  `healthChecks`/`healthCheckExprs` if the source had them.
- `targetNamespace` is redundant with `base/kustomization.yaml`'s `namespace:` field but harmless;
  drop it if the source had it, don't add it if not.
- `dependsOn`: carry over any sibling dependency from the source (e.g. `onepassword-connect` →
  `dependsOn: external-secrets`, `kopiur-repository` → `dependsOn: kopiur`). Additionally, for
  **`k8s/infra` components only**, default to `dependsOn: - name: infra-ns` (the namespace-creating
  Flux Kustomization) — **unless** this component is one of the small set installed by `helmfile`
  during cluster bootstrap before Flux even runs (currently: `cilium`, `sealed-secrets`,
  `cert-manager`, `flux-operator`, `flux-instance`), where the namespace already exists by the time
  this Kustomization reconciles. If unsure whether a component belongs to that bootstrap set, ask
  rather than guessing. `k8s/apps` components don't need `dependsOn: infra-ns` (their namespace is
  self-contained, see step 5).

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: <component>
spec:
  dependsOn:
    - name: infra-ns
  interval: 1h
  path: ./k8s/infra/<namespace>/<component>/base
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  wait: true
```

## 4. `k8s/infra` only — namespace registration

Check whether `k8s/infra/<namespace>/_ns/base/` already exists (e.g. porting a second component into
an already-ported namespace, like `onepassword-connect` reusing `external-secrets`' namespace) —
**create it only once per namespace**:

```yaml
# k8s/infra/<namespace>/_ns/base/ns.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: _
  annotations:
    kustomize.toolkit.fluxcd.io/prune: disabled
```

```yaml
# k8s/infra/<namespace>/_ns/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: <namespace>

resources:
  - ns.yaml
```

Then register it (alphabetically) in `k8s/infra/common/ns/base/kustomization.yaml`'s `resources:`
list as `- ../../../<namespace>/_ns/base`. Nothing else needs touching — every env's
`k8s/infra/common/ns/envs/<env>/kustomization.yaml` just composes `../../base`, so this one edit
propagates everywhere.

## 5. `k8s/apps` only — self-contained namespace

Apps don't split namespace creation out to `_ns` or register centrally. Instead add `ns.yaml` directly
to the component's `base/` and list it first in `base/kustomization.yaml`'s `resources:` (see
`k8s/apps/diag/whoami/base/` for the pattern). No `dependsOn: infra-ns` is needed in `flux/ks.yaml`.

## 6. Register in the flux set

Append (alphabetically, by full relative path) one line per new component's `flux/` directory to the
chosen set file:
- infra: `k8s/bootstrap/cluster/flux/sets/infra/{minimal,optional}/kustomization.yaml`
- apps: `k8s/bootstrap/cluster/flux/sets/apps/{minimal,optional}/kustomization.yaml`

```yaml
  - ../../../../../../infra/<namespace>/<component>/flux
```

(six `../` levels for infra/apps sets — count the existing entries in the target file to confirm depth
rather than assuming.)

## 7. Special case: bootstrap-time secrets (rare — flag, don't auto-apply)

If (and only if) the ported component is itself part of the secrets-bootstrap chain — i.e. it needs a
`Secret` to exist *before* External Secrets Operator / the `ClusterSecretStore` can resolve `op://`
references for it, a chicken-and-egg problem — this repo has a documented escape hatch
(`k8s/bootstrap/kustomize/personal/<component>/{kustomization.yaml,s3cr3t.yaml}`, injected via `op
inject` during `just bootstrap::cluster`, registered in `k8s/bootstrap/kustomize/personal/kustomization.yaml`
and `k8s/bootstrap/mod.just`) and sometimes needs the component installed as a `helmfile` release
(`k8s/bootstrap/helmfile/apps/helmfile.yaml.gotmpl`) instead of purely via Flux. This is what commit
`3be16891...` did for `external-secrets`/`onepassword-connect` themselves. **Do not replicate this
pattern automatically** — it's specific to components that participate in bootstrapping secrets
management. Flag it to the user and point at that commit as precedent; let them decide.

## 8. Validate before committing

```sh
kustomize build k8s/infra/<namespace>/<component>/envs/dev
kustomize build k8s/infra/<namespace>/<component>/flux
kustomize build k8s/infra/common/ns/base   # if you touched namespace registration
kustomize build k8s/bootstrap/cluster/flux/sets/infra/minimal   # or whichever set you edited
```
Run `pre-commit run --files <changed files>` if pre-commit is installed. Don't commit unless asked —
present the new file tree and a short summary, follow this repo's Conventional Commits + path-scope
convention (see root `CLAUDE.md`) for the message, e.g. `feat: <component>` or
`feat(base/<component>): ...`.
