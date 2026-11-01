# kubelet-serving-cert-approver

[kubelet-serving-cert-approver](https://github.com/alex1989hu/kubelet-serving-cert-approver) approves the certificate signing requests (CSRs) that kubelets create for their serving certificates.

## At a glance

| | |
| --- | --- |
| Namespace | `kubelet-serving-cert-approver` (created by the vendored manifest) |
| Runs in | all 8 environments (Flux set `minimal`) |
| Installed via | The upstream release manifest `standalone-install.yaml`, vendored under [`base/vendor/`](base/vendor/) |
| Flux Kustomization | `k-serving-cert-approver`, no `dependsOn` |

## Purpose

The kubelets are configured with `rotate-server-certificates: true` (in the Talos machine config of each environment's `vehagn-k8s` unit), so each one asks the API server for a serving certificate signed by the cluster CA. Kubernetes does not approve such CSRs by itself; this controller does, after checking that the request matches the node. Without it the kubelet falls back to a self-signed certificate and clients that verify it (`metrics-server`, `kubectl top`) fail.

## Where it is used

- **Used by**: the kubelets of every node, and indirectly by [`metrics-server`](../../../apps/monitoring/metrics-server/) and anything else that verifies kubelet TLS.
- **Depends on**: the API server only.

## Access

Not exposed.

## Updates

- **Version**: the release number is in the upstream URL comment of [`base/kustomization.yaml`](base/kustomization.yaml), next to the file under `base/vendor/`.
- **Flow**: Renovate bumps the URL; run `scripts/vendor-manifests.sh update` on that PR branch to fetch the matching file (the `kustomize-build` check fails until it matches). Details: [`update-handling.md`](../../../../docs/operations/update-handling.md#renovate). No other Renovate rule applies.

## Operations

Nothing specific. A node whose kubelet certificate stays pending: see the cheat sheet.

## Cheat sheet

```sh
flux get ks k-serving-cert-approver --context admin@<env>-homelab
kubectl get pods -n kubelet-serving-cert-approver --context admin@<env>-homelab

# pending or approved serving-certificate requests
kubectl get csr --context admin@<env>-homelab | grep kubelet-serving
kubectl logs -n kubelet-serving-cert-approver deploy/kubelet-serving-cert-approver --context admin@<env>-homelab

# fetch the vendored file for the version in the URL comment, then check
scripts/vendor-manifests.sh update
scripts/vendor-manifests.sh check
```

## Upstream

- Source and releases: <https://github.com/alex1989hu/kubelet-serving-cert-approver>
