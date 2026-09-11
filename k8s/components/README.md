## Purpose

One of the main goals of this folder is to provide a set of common components that can be used across multiple applications and environments, reducing duplication and promoting consistency.

A typical use case is transforming the domain name `example.com` defined in the applications' base configuration to `your.sub.domain.com` across all applications and environments. Another use case is setting common labels, annotations, or resource limits.

These components can then be included in the `kustomization.yaml` files of individual applications and environments, allowing for easy customization and extension.

## Folder Structure

```
📁 components
├── 📁 apps                     # application-specific configuration
│   ├── 📁 kopiur                 # kopiur backup credential wiring (per-namespace secret)
│   └── 📁 storage                # PVC provisioning for apps, with or without backup -- see its own README
├── 📁 envs                     # environment-specific configuration
│   ├── 📁 base                 # sourced and reused in the env-specific overlays
│   ├── 📁 dev                  # dev environment-specific configuration
│   ├── 📁 ...                    (sourced in fooapp/envs/dev)
│   └── 📁 prod                 # prod environment-specific configuration
└── 📁 transformers             # kustomize transformers used in the components above
    ├── 📁 add-labels           # add labels to resources, e.g. reconcile.fluxcd.io/watch: "Enabled"
    ├── 📁 kopiur-secret-env    # rewrite kopiur's per-env 1Password key + ClusterRepository bucket name
    ├── 📁 prefix-domain        # prefix domain with env., e.g. dev-app.example.com
    ├── 📁 replace-domain       # rename base domain example.com to your.sub.domain.com
    ├── 📁 replace-path         # replace base path by environment-specific path in configuration files (flux)
    ├── 📁 set-flux-defaults    # set default values for flux configuration files
    └── 📁 suspend-kopiur-schedule  # force-suspend kopiur SnapshotSchedules in environments without active backup
```

See each subfolder's own README for details -- `k8s/components/apps/<app>/README.md` and
`k8s/components/transformers/<name>/README.md`, where present.
