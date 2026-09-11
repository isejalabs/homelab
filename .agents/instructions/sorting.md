# Sorting instructions for all YAML files

Whenever asked to sort these files, follow these instructions:

- **Default rule**: all fields and properties should be sorted alphabetically at every level of the YAML structure, regardless of how deeply nested they are, unless a specific override rule is provided below.

(Adapted from [mirceanton/home-ops](https://github.com/mirceanton/home-ops)'s `.agents/instructions/sorting.md` — the default rule and the two rules directly below are his; everything from "kustomize `kustomization.yaml`/`Component` files" onward is specific to this repo.)

## Override rules for Kubernetes-related file types

- Whenever they are present at the same level of a YAML structure, these fields should be sorted as follows:
  - `apiVersion`
  - `kind`
  - `metadata`
  - `spec`

- The items within the `metadata` section should be sorted as follows:
  - `name`
  - `namespace`
  - `annotations`
  - `labels`

## kustomize `kustomization.yaml`/`Component` files

This covers every `kustomization.yaml` in `k8s/` — `kind: Kustomization` (bases, overlays, and the shared `components/envs/<env>` includes) and `kind: Component` (`components/transformers/*`). These files have **no `spec`** — the standard K8s object rule above doesn't apply; use this section instead.

### Top-level key order

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization # or: Component

namespace: <ns> # + namePrefix/nameSuffix/labels/commonAnnotations, if present — global modifiers, read first

components: # shared/reusable layer (e.g. ../../../../../components/envs/<env>) — sourced first
  - ...

resources: # this unit's own specifics (own manifests, or ../../base) — layered on top of components
  - ...

configMapGenerator: # generators — synthesize additional operands from local data
  - ...
secretGenerator:
  - ...
generatorOptions:

patches: # tweaks applied last, against the full assembled set (components + resources + generated)
  - ...

replacements: # cross-cutting field copies — same "applied last" tier as patches
  - ...
transformers:
```

Rationale:

- `namespace` and other simple global modifiers first — cheap to read, and generators/patches below may depend on them (e.g. `configMapGenerator` needs `namespace` to already be set).
- `components` before `resources`: the shared, reusable layer every overlay builds on is sourced first; this unit's own specifics are layered on top of it — not the other way round.
- Generators (`configMapGenerator`/`secretGenerator`/`generatorOptions`) after `resources`: they produce additional operands the same way `resources` does, just synthesized rather than authored, so group them with what they're adjacent to.
- `patches` last, before `replacements`/`transformers`: patches apply against the *whole* resource set (components + resources + generated), so they're ordered after everything they might target.

Do not follow `sigs.k8s.io/kustomize`'s Go struct field order (`api/types/kustomization.go`) for this — it interleaves several deprecated fields (`bases`, `patchesStrategicMerge`, `imageTags`, `vars`) and puts modifiers *before* operands and `patches` *before* `resources`/`components`, which reads backwards for a human skimming the file. It's fine as a last-resort tie-breaker for a field not listed above, never as the primary convention.

### List entries within a section

- Default to alphabetical (e.g. `components/*/kustomization.yaml`'s app registration lists).
- Grouping is fine, and takes precedence over alphabetizing, when entries are tightly coupled and the grouping itself communicates something (e.g. a `db`/`frontend` manifest pair in `resources:`, or patches listed in the order they conceptually layer). Don't break up an existing intentional grouping just to alphabetize it.

## Flux `Kustomization` (`ks.yaml`)

The standard K8s object rule above (`apiVersion`/`kind`/`metadata`/`spec`) applies, and within `spec`, fields are alphabetical **except `dependsOn`, which always goes last** — it's optional dependency wiring, not a core reconciliation setting, and every `ks.yaml` in this repo already puts it after `wait`:

```yaml
spec:
  interval: 1h
  path: ./k8s/...
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  wait: true
  dependsOn: # always last, if present
    - name: ...
```
