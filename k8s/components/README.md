## Purpose

One of the main goals of this folder is to provide a set of common components that can be used across multiple applications and environments, reducing duplication and promoting consistency.

A typical use case is transforming the domain name `example.com` defined in the applications' base configuration to `your.sub.domain.com` across all applications and environments. Another use case is setting common labels, annotations, or resource limits.

These components can then be included in the `kustomization.yaml` files of individual applications and environments, allowing for easy customization and extension.

## Folder Structure

```
📁 components
├── 📁 apps                 # application-specific configuration
├── 📁 envs                 # environment-specific configuration
│   ├── 📁 base             # sourced and reused in the env-specific overlays
│   ├── 📁 dev              # dev environment-specific configuration
│   ├── 📁 ...                (sourced in fooapp/envs/dev)
│   └── 📁 prod             # prod environment-specific configuration
└── 📁 transformers         # kustomize transformers used in the components above
    ├── 📁 prefix-domain    # prefix domain with env., e.g. dev-app.example.com
    ├── 📁 replace-domain   # rename base domain example.com to your.sub.domain.com
    └── 📁 replace-path     # replace base path by environment-specific path in configuration files (flux)
```