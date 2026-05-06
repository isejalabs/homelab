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

See also

- [terragrunt/README.md](terragrunt/README.md) for the bootstrapping of the Kubernetes cluster by deploying VMs in Proxmox, installing Talos and deploying core infrastructure such as Cilium CNI and Proxmox CSI,
- [k8s/README.md](k8s/README.md) for deployment of apps in the Kubernetes cluster.
