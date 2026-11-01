# Gateway API CRDs

The upstream [Gateway API](https://gateway-api.sigs.k8s.io/) custom resource definitions: `GatewayClass`, `Gateway`, `HTTPRoute` and friends from the standard channel, plus the experimental `TLSRoute`.

## At a glance

| | |
| --- | --- |
| Namespace | `gateway-api` (cluster-scoped CRDs; the namespace is where the [`gateway`](../gateway/README.md) unit lives) |
| Runs in | all 8 environments (Flux set `minimal`) |
| Installed via | Upstream release manifests, vendored under [`base/vendor/`](base/vendor/): `standard-install.yaml` and the experimental `TLSRoute` CRD |
| Flux Kustomization | `gateway-api-crds`, no `dependsOn` |

## Purpose

Cilium implements the Gateway API but does not ship its CRDs. They are installed from the upstream release instead of a chart, and the experimental `TLSRoute` is added because the TLS passthrough Gateway in `poc` needs it.

## Where it is used

- **Used by**: [`gateway`](../gateway/README.md) and every `HTTPRoute` in the repo, and [Cilium](../../kube-system/cilium/README.md), whose Gateway controller reads them.
- **Depends on**: the API server only. Units that use Gateway API resources `dependsOn` `gateway-api` or `gateway-api-crds`, so the CRDs exist before their first reconcile.

## Access

Not exposed.

## Updates

- **Version**: the release number is in the two upstream URL comments of [`base/kustomization.yaml`](base/kustomization.yaml) (they must be equal), next to the files under `base/vendor/`.
- **Flow**: Renovate bumps the URLs; run `scripts/vendor-manifests.sh update` on that PR branch to fetch the matching files (the `kustomize-build` check fails until they match): [`update-handling.md`](../../../../docs/operations/update-handling.md#renovate).
- **Pinned**: Renovate allows `<=1.4` for Cilium compatibility; `head` and `poc` are the exception that track newer releases, labeled `updateStrategy:pinWatch`: [Non-standard update strategies](../../../../docs/operations/update-handling.md#non-standard-update-strategies). Raise the cap only together with a Cilium version that supports the newer API.

## Operations

Nothing specific. Flux problems: [`troubleshooting-flux.md`](../../../../docs/troubleshooting/troubleshooting-flux.md).

## Cheat sheet

```sh
flux get ks gateway-api-crds --context admin@<env>-homelab
kubectl get crd --context admin@<env>-homelab | grep gateway.networking.k8s.io

# installed API version of the Gateway API bundle
kubectl get crd gateways.gateway.networking.k8s.io --context admin@<env>-homelab -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}'

# fetch the vendored files for the version in the URL comments, then check
scripts/vendor-manifests.sh update
scripts/vendor-manifests.sh check
```

## Upstream

- Documentation: <https://gateway-api.sigs.k8s.io/>
- Source and releases: <https://github.com/kubernetes-sigs/gateway-api>
