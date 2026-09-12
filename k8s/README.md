## ToDo

- [ ] document folder structure
- [X] document bootstrap process (incl. manual steps and automation via CI/CD pipelines)

## Kustomize overlay approach

See [`docs/architecture/kustomize.md`](../docs/architecture/kustomize.md) for how the `base`/`envs/<env>`/`flux`
overlay triad, overlay patches, the shared `components` layer, and its `replacements`-based transformers
(domain rewriting, common labels, Flux `spec.path`/`spec.interval` rewriting) fit together.
