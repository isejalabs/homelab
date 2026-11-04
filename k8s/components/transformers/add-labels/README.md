## Purpose

Stamps the label `reconcile.fluxcd.io/watch: "Enabled"` onto every `ConfigMap` in the build. Flux's Helm Controller only watches a `ConfigMap` that carries this label, so a change to one that a `HelmRelease` takes its values from (`valuesFrom`, e.g. `cilium-base-values` for [`cilium`](../../../infra/kube-system/cilium/README.md)) upgrades that release immediately instead of at the next `spec.interval`.

Without the transformer every app that generates such a `ConfigMap` would have to repeat the label by hand, and forgetting it would fail silently: the new values would only apply after the next reconciliation.

## How it works

The only transformer here that does not use `replacements`: it is a built-in kustomize `LabelTransformer` ([`transf/label-ConfigMaps.yaml`](transf/label-ConfigMaps.yaml)). `create: true` adds `metadata.labels` to a `ConfigMap` that has none, so the label lands on every `ConfigMap`, not only on those that already carry labels:

```yaml
apiVersion: builtin
kind: LabelTransformer
metadata:
  name: label-ConfigMaps
fieldSpecs:
  - kind: ConfigMap
    create: true
    path: metadata/labels
labels:
  reconcile.fluxcd.io/watch: "Enabled"
```

A build without any `ConfigMap` is unchanged, so the transformer is safe to include everywhere.

## Where it's included

Through [`components/envs/base`](../../envs/base/kustomization.yaml), which every environment's component includes, so all 8 environments get it unconditionally. It comes together with `replace-domain`, `replace-path` and `set-flux-defaults`; dropping it from one environment would mean no longer including `../base` there.

See [`docs/architecture/kustomize.md`](../../../../docs/architecture/kustomize.md#transformers-and-replacements) for how the transformers fit together.
