> [!NOTE]
> For a walkthrough of how these components fit into the overall `base`/`envs/<env>`/`flux` overlay
> approach, with concrete examples of the `replacements` each transformer uses, see
> [`docs/architecture/kustomize.md`](../../docs/architecture/kustomize.md).

## Purpose

One of the main goals of this folder is to provide a set of common components that can be used across multiple applications and environments, reducing duplication and promoting consistency.

A typical use case is transforming the domain name `example.com` defined in the applications' base configuration to `your.sub.domain.com` across all applications and environments. Another use case is setting common labels, annotations, or resource limits.

These components can then be included in the `kustomization.yaml` files of individual applications and environments, allowing for easy customization and extension.

## Folder Structure

```
📁 components
├── 📁 apps                         # application-specific configuration
│   ├── 📁 kopiur                   # kopiur backup credential wiring (per-namespace secret)
│   └── 📁 storage                  # PVC provisioning for apps, with or without backup
├── 📁 envs                         # environment-specific configuration
│   ├── 📁 base                     # sourced and reused in the env-specific overlays
│   ├── 📁 dev                      # dev environment-specific configuration
│   ├── 📁 ...                      # one folder per environment, sourced in fooapp/envs/<env>
│   └── 📁 prod                     # prod environment-specific configuration
└── 📁 transformers                 # kustomize transformers used in the components above
    ├── 📁 add-labels               # add labels to resources, e.g. reconcile.fluxcd.io/watch: "Enabled"
    ├── 📁 kopiur-secret-env        # rewrite kopiur's per-env 1Password key + ClusterRepository bucket name
    ├── 📁 powerdns-tsig-env        # rewrite powerdns's per-env TSIG-key 1Password keys
    ├── 📁 prefix-domain            # prefix domain with env., e.g. dev-app.example.com
    ├── 📁 replace-domain           # rename base domain example.com to your.sub.domain.com
    ├── 📁 replace-path             # replace base path by environment-specific path in configuration files (flux)
    ├── 📁 reverse-zone-env         # wire each env's own PTR-zone name into powerdns + external-dns
    ├── 📁 set-flux-defaults        # set default values for flux configuration files
    └── 📁 suspend-kopiur-schedule  # force-suspend kopiur SnapshotSchedules in environments without active backup
```

Every subfolder of `apps/` and `transformers/` has its own README: [`apps/kopiur`](apps/kopiur/README.md), [`apps/storage`](apps/storage/README.md) and the transformers below.

| Transformer | What it rewrites | Included in |
| --- | --- | --- |
| [`add-labels`](transformers/add-labels/README.md) | stamps `reconcile.fluxcd.io/watch` on every `ConfigMap`, so Flux upgrades a `HelmRelease` as soon as its values change | all 8 (via `envs/base`) |
| [`kopiur-secret-env`](transformers/kopiur-secret-env/README.md) | kopiur's per-env 1Password key and `ClusterRepository` bucket name | all 8, per environment |
| [`powerdns-tsig-env`](transformers/powerdns-tsig-env/README.md) | PowerDNS's per-env TSIG-key 1Password keys and AXFR key name | all 8, per environment |
| [`prefix-domain`](transformers/prefix-domain/README.md) | puts the environment name in front of a hostname (`dev-app.dev.iseja.net`) | all but `prod`, per environment |
| [`replace-domain`](transformers/replace-domain/README.md) | swaps the placeholder domain `example.com` for the environment's domain | all 8 (via `envs/base`) |
| [`replace-path`](transformers/replace-path/README.md) | points every Flux `Kustomization` at `envs/<env>` instead of `base` | all 8 (via `envs/base`) |
| [`reverse-zone-env`](transformers/reverse-zone-env/README.md) | each environment's own PTR-zone name into PowerDNS and external-dns | all 8, per environment |
| [`set-flux-defaults`](transformers/set-flux-defaults/README.md) | the reconciliation interval of every Flux `Kustomization`/`HelmRelease` and the retry interval of every `Kustomization` | all 8 (via `envs/base`) |
| [`suspend-kopiur-schedule`](transformers/suspend-kopiur-schedule/README.md) | force-suspends every kopiur `SnapshotSchedule` | `dbg`, `head`, `poc`, `src`, per environment |
