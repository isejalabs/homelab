# metrics-server

[metrics-server](https://github.com/kubernetes-sigs/metrics-server) serves the Kubernetes resource metrics API (`metrics.k8s.io`): CPU and memory per node and pod, as used by `kubectl top` and by a HorizontalPodAutoscaler.

## At a glance

| | |
| --- | --- |
| Namespace | `kube-system` |
| Runs in | all 8 environments (Flux set `minimal`) |
| Installed via | HelmRelease, chart from the OCI repository `ghcr.io/home-operations/charts-mirror/metrics-server` ([`base/ocirepository.yaml`](base/ocirepository.yaml)), default values |
| Flux Kustomization | `metrics-server`, no `dependsOn` |

## Purpose

Makes `kubectl top nodes|pods` work and gives autoscaling a source. It is not a monitoring system: it keeps no history. Monitoring is Checkmk, see [`checkmk-agent`](../checkmk-agent/README.md) and [`monitoring.md`](../../../../docs/architecture/monitoring.md).

## Where it is used

- **Used by**: people running `kubectl top`, and any HorizontalPodAutoscaler (none in this repo today).
- **Depends on**: the kubelets' serving certificates, which [`kubelet-serving-cert-approver`](../../../infra/kube-system/kubelet-serving-cert-approver/) approves.

## Access

Not exposed. It registers itself as the `v1beta1.metrics.k8s.io` APIService.

## Updates

- **Chart**: tag and digest in [`base/ocirepository.yaml`](base/ocirepository.yaml). The chart comes from a mirror maintained by the home-operations community (not from the upstream chart repository). No special Renovate rule: the default flow of [`update-handling.md`](../../../../docs/operations/update-handling.md) applies.

## Operations

Nothing specific. Flux problems: [`troubleshooting-flux.md`](../../../../docs/troubleshooting/troubleshooting-flux.md).

## Cheat sheet

```sh
flux get ks metrics-server --context admin@<env>-homelab
kubectl get apiservice v1beta1.metrics.k8s.io --context admin@<env>-homelab
kubectl top nodes --context admin@<env>-homelab
kubectl top pods -A --sort-by=memory --context admin@<env>-homelab
```

If `kubectl top` answers `Metrics API not available`, check the APIService is `Available` and the pod's logs (`kubectl logs -n kube-system deploy/metrics-server`).

## Upstream

- Source and releases: <https://github.com/kubernetes-sigs/metrics-server>
- Chart: `oci://ghcr.io/home-operations/charts-mirror/metrics-server`
