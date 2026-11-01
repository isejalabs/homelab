# Flux Operator

The ControlPlane [Flux Operator](https://github.com/controlplaneio-fluxcd/flux-operator) manages the lifecycle of the Flux controllers through a `FluxInstance` resource ([`flux-instance`](../flux-instance/README.md)) and ships a web UI for Flux.

## At a glance

| | |
| --- | --- |
| Namespace | `flux-system` |
| Runs in | all 8 environments (Flux set `minimal`); installed by the bootstrap helmfile after `cert-manager`, then taken over by Flux (it manages itself) |
| Installed via | HelmRelease, chart from the OCI repository `ghcr.io/controlplaneio-fluxcd/charts/flux-operator` ([`base/ocirepository.yaml`](base/ocirepository.yaml)), plus an `HTTPRoute` for the web UI |
| Flux Kustomization | `flux-operator`, depends on `infra-ns` |

## Purpose

Installs, configures and upgrades Flux from a declarative `FluxInstance` instead of `flux bootstrap`, and offers a UI that shows Flux resources, their health and events. Why Flux and not Argo CD: [ADR 0009](../../../../docs/decisions/0009-flux-vs-argocd.md).

## Where it is used

- **Used by**: [`flux-instance`](../flux-instance/README.md), which it reconciles into the actual controllers; people who open the UI.
- **Depends on**: the API server only. At bootstrap it needs `cert-manager` (see the order in [`workloads.md`](../../../../docs/architecture/workloads.md#bootstrap-install-order)).

## Access

The web UI is published through the `internal` Gateway under the subdomain `flux`.

| env | URL |
| --- | --- |
| `dbg` | `https://dbg-flux.dbg.iseja.net` |
| `dev` | `https://dev-flux.dev.iseja.net` |
| `head` | `https://head-flux.head.iseja.net` |
| `poc` | `https://poc-flux.poc.iseja.net` |
| `prod` | `https://flux.prod.iseja.net` |
| `qa` | `https://qa-flux.qa.iseja.net` |
| `rebuild` | `https://rebuild-flux.rebuild.iseja.net` |
| `src` | `https://src-flux.src.iseja.net` |

Hostname scheme: [`reference/environments.md`](../../../../docs/reference/environments.md#domain-and-naming).

## Updates

- **Chart**: tag and digest in [`base/ocirepository.yaml`](base/ocirepository.yaml). Keep it in step with [`flux-instance`](../flux-instance/README.md) (same release train). No special Renovate rule: the default flow of [`update-handling.md`](../../../../docs/operations/update-handling.md) applies.

## Operations

| Task | Doc |
| --- | --- |
| A `Kustomization` or `HelmRelease` is stuck | [`troubleshooting-flux.md`](../../../../docs/troubleshooting/troubleshooting-flux.md) |
| Test a branch in a live environment | the `track-branch` skill, see [`update-handling.md`](../../../../docs/operations/update-handling.md#how-environments-actually-differ-for-update-handling) |

## Cheat sheet

```sh
flux get ks -A --context admin@<env>-homelab
flux get hr -A --context admin@<env>-homelab
kubectl get fluxinstance -n flux-system --context admin@<env>-homelab
kubectl get pods -n flux-system --context admin@<env>-homelab
```

## Upstream

- Homepage and documentation: <https://fluxcd.control-plane.io/operator/>
- Source and releases: <https://github.com/controlplaneio-fluxcd/flux-operator>
