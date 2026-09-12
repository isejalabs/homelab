## UNDER CONSTRUCTION

That mono-repo is still in an evolving state with several PoCs (proof-of-concepts), i.e. _not_ containing any fully-fledged k8s/homelab implementation, yet.

Nevertheless, you can find some interesting PoCs for

- docker-compose implementation for unifi network controller (the new version requires separation from the mongo db container)
- talhelper (for talos) feat. environment-specific definitions (DRY)
- tofu (terraform) code for IaC-ing proxmox VMs, needed for talos
- terragrunt for even more IaC, thus allowing the use of versioned terraform/tofu modules for several environments
- k8s apps definition leveraging `kustomize`'s patching and transformer capabilities for defining a base and dev/staging/prod (similar to the environment-specfic course done for talhelper and terragrunt/tofu)

It's all about IaC and DRY -- and my future homelab (based on [vehagn/homelab](https://github.com/vehagn/homelab)) :-)

## Documentation

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/isejalabs/homelab) gives a good overview of the current state of the implementation of my homelab repo, and is being updated on a regular basis.

### Folder Structure

```
📁 homelab
├── 📁 terragrunt      # OpenTofu/Terragrunt IaC: provisions Proxmox VMs and installs Talos Linux (see terragrunt/README.md)
├── 📁 k8s             # cluster bootstrap + the infra/apps Flux reconciles + the shared DRY kustomize components layer (see k8s/README.md)
├── 📁 scripts         # helper shell scripts (SOPS bulk ops, terragrunt state cleanup, k8s upgrade)
├── 📁 docs            # cross-cutting architecture docs, procedural notes, and bootstrap logs (see docs/README.md)
├── 📁 .agents         # shared agent instructions/skills (YAML sorting conventions, track-branch, port-app)
├── 📁 .commons        # git submodule: AI-agent conventions shared across isejalabs repos
├── 📁 .github         # issue/PR automation config (labeler, Renovate, Mergify)
├── 📁 .claude         # Claude Code project skills
├── 📁 .ci             # CI tooling config (prettier)
└── 📁 _attic          # retired/old material, not part of the active implementation
```

Root-level config files (`.sops.yaml`, `.pre-commit-config.yaml`, `.justfile`, `.minijinja.toml`, `.gitmodules`) wire up SOPS, pre-commit hooks, the `just` command runner and templating.

For the detailed layout of each major area, see also

- [terragrunt/README.md](terragrunt/README.md) for the Terragrunt folder structure, and the bootstrapping of the Kubernetes cluster by provisioning VMs in Proxmox, installing Talos and deploying core infrastructure such as Cilium CNI and Proxmox CSI setup,
- [k8s/README.md](k8s/README.md) for the k8s folder structure (`apps/`, `bootstrap/`, `components/`, `infra/`, `test/`) and the shared `base`/`envs`/`flux` shape every app/infra unit follows,
- [k8s/bootstrap/README.md](k8s/bootstrap/README.md) for deployment of infrastructure components and apps in the Kubernetes cluster,
- [k8s/components/README.md](k8s/components/README.md) for the shared DRY kustomize components layer,
- [docs/README.md](docs/README.md) for cross-cutting architecture docs (e.g. the kustomize overlay approach) versus per-folder usage READMEs,
