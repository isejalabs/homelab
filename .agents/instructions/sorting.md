# Sorting instructions for all YAML files

Follow these instructions whenever creating or editing a YAML file — not just when explicitly asked to sort one. This includes new files, files patched/ported in from another repo (e.g. via the `port-app` skill), and any other write to an existing file that touches ordering. An explicit "sort this file" request re-applies the same rules to a file's current content.

- **Default rule**: all fields and properties should be sorted alphabetically at every level of the YAML structure, regardless of how deeply nested they are, unless a specific override rule is provided below.

## Override rules for Kubernetes-related file types

- **Whenever they are present, these fields lead any mapping, at any level, ahead of everything else in it** — not just a resource's root, but any nested mapping shaped like an object reference too (a kustomize `replacements` `source`/`select`, a Flux `sourceRef`/`roleRef`/`secretKeyRef`, a Gateway API `parentRef`/`backendRef`, a container, an env var, a BGP peer, ...):
  - `apiVersion`
  - `kind`
  - `metadata`
  - `name` (or `id`, only when `name` isn't present)
  - `namespace`
  - `spec`

  Only the fields actually present in a given mapping take part — skip any that are missing rather than leaving a gap for them. Sort everything else in that mapping alphabetically after this list.

  `kind`/`apiVersion` leading `name` matters even outside a full resource: a bare `{kind: ConfigMap, name: cluster-param}` reference should still read "this kind of thing, named this" rather than alphabetical order flipping it to name-first. And `name`/`id` alone (with no `kind`/`apiVersion` in the same mapping) is what makes a plain container, env var, or list entry lead with its own identity — e.g. a container's `image` would otherwise sort before its `name`.

  This is deliberately narrower than "any field that identifies something": a merely-common word like `group` was considered and rejected, since it's ambiguous outside a Gateway API type reference (e.g. `AdGuardHome.yaml`'s `os.group`, an OS group name, has nothing to do with an API group) — `apiVersion`/`kind`/`metadata`/`name`/`id`/`namespace`/`spec` are safe because they're reserved Kubernetes vocabulary that doesn't mean something else.

- The items within the `metadata` section specifically should be sorted as follows (its own, narrower rule — not just alphabetical, since `annotations` would otherwise sort before `labels` before `namespace`):
  - `name`
  - `namespace`
  - `annotations`
  - `labels`

## Gateway API route rules (`HTTPRoute`/`GRPCRoute`/`TCPRoute`/`TLSRoute` `spec.rules`)

Each entry in `spec.rules` should read in request-processing order — what to match, what to do to it, where to send it — rather than alphabetically:

```yaml
rules:
  - name: ... # if present (Gateway API rule naming) — leading identifier, per the name/id rule above
    matches: # what triggers this rule
      - ...
    filters: # what happens to a matching request, if anything
      - ...
    backendRefs: # where a (possibly filtered) request is sent
      - ...
```

Anything else on the rule (e.g. `timeouts`, `sessionPersistence`) sorts alphabetically after `backendRefs`. This is a narrower case of the same principle as `kustomize`'s top-level layout above: reading order over alphabetical order when alphabetical would scramble a mapping's actual data flow.

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
