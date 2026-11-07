# Flux instance

The `FluxInstance` resource: the actual Flux controllers (source, kustomize, helm, notification), pointed at this repository. Installing it is the hand-off from the bootstrap to Flux.

## At a glance

| | |
| --- | --- |
| Namespace | `flux-system` |
| Runs in | all 8 environments (Flux set `minimal`); the last step of the bootstrap helmfile |
| Installed via | HelmRelease, chart from the OCI repository `ghcr.io/controlplaneio-fluxcd/charts/flux-instance` ([`base/ocirepository.yaml`](base/ocirepository.yaml)); the sync target is set per environment in `envs/<env>/helmrelease.yaml` |
| Flux Kustomization | `flux-instance`, no `dependsOn` |

## Purpose

Defines which Flux components run, which distribution they come from and what they reconcile: `sync` points at `k8s/bootstrap/cluster/flux/envs/<env>` on the ref `refs/heads/main` of this repository, every 10 minutes. The leader election is relaxed to write less to etcd, and the helm-controller retries a failed install indefinitely (`DefaultToRetryOnFailure`).

## Where it is used

- **Used by**: everything: this is the controller set that reconciles all units of all environments.
- **Depends on**: [`flux-operator`](../flux-operator/README.md), which turns the resource into controllers.

## Access

Not exposed. The web UI is that of [`flux-operator`](../flux-operator/README.md).

## Updates

- **Chart**: tag and digest in [`base/ocirepository.yaml`](base/ocirepository.yaml); the Flux distribution (`distribution.artifact`) in [`base/helmrelease.yaml`](base/helmrelease.yaml). No special Renovate rule: the default flow of [`update-handling.md`](../../../../docs/operations/update-handling.md) applies.
- **Which branch an environment follows**: `main` everywhere. To test a branch live in a non-prod environment, use the `track-branch` skill, which uncomments the `ref` line in that environment's `envs/<env>/helmrelease.yaml` in a throwaway `tmp(<env>)` commit and applies it directly; never for `prod`: [`update-handling.md`](../../../../docs/operations/update-handling.md#how-environments-actually-differ-for-update-handling).

## Operations

| Task | Doc |
| --- | --- |
| Bootstrap or re-sync an environment | [`k8s/bootstrap/README.md`](../../../bootstrap/README.md) |
| A `Kustomization` or `HelmRelease` is stuck | [`troubleshooting-flux.md`](../../../../docs/troubleshooting/troubleshooting-flux.md) |

## Cheat sheet

```sh
kubectl get fluxinstance -n flux-system --context admin@<env>-homelab
flux get sources git -A --context admin@<env>-homelab      # which ref, which revision
flux get ks -A --context admin@<env>-homelab

# reconcile the repository and all units now
flux reconcile source git flux-system --context admin@<env>-homelab
flux reconcile ks flux-system --with-source --context admin@<env>-homelab
```

## Upstream

- Documentation: <https://fluxcd.io/>, <https://fluxcd.control-plane.io/operator/flux-instance/>
- Source and releases: <https://github.com/controlplaneio-fluxcd/flux-operator>
