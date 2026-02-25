# ArgoCD

## Links
- https://github.com/mitchross/talos-argocd-proxmox
- https://spacelift.io/blog/flux-vs-argo-cd
- [Handling Helm+Kustomize in your rendering - Discussion](https://github.com/akuity/kargo/discussions/3208)
- [The Art of Argo CD ApplicationSet Generators with Kubernetes](https://piotrminkowski.com/2025/03/20/the-art-of-argo-cd-applicationset-generators-with-kubernetes/)
- [How to Use ArgoCD Environment Variables in Helm, Ingress, and App of Apps](https://akuity.io/blog/argo-cd-build-environment-examples)
- [Argo CD and Kargo Showcase](https://github.com/piomin/argocd-showcase)
App Dependendencies
- [Managing Application Dependencies in Argo CD - Christian Hernandez, Akuity - YouTube](https://youtu.be/QKyOOPWXnIA)
- [Child applications should not effect parent application's health by default](https://github.com/argoproj/argo-cd/issues/3781)
- [Application dependencies](https://github.com/argoproj/argo-cd/issues/7437)

## Cheat Sheet
### get initial admin secret

```sh
k get -n argocd secret argocd-initial-admin-secret -ojson | jq -r ' .data.password | @base64d'
```

### list all applications deployed

```sh
k get applications -A
```

#### Example Output

```text
NAMESPACE   NAME                                  SYNC STATUS   HEALTH STATUS
argocd      app-adguard                           Synced        Healthy
argocd      app-checkmk-agent                     Synced        Healthy
argocd      app-metrics-server                    Synced        Healthy
argocd      app-unbound                           Synced        Healthy
argocd      app-unifi-controller                  Synced        Healthy
argocd      app-whoami                            Synced        Healthy
argocd      core-cilium                           Synced        Healthy
argocd      core-gateway                          Synced        Healthy
argocd      core-sealed-secrets                   Synced        Healthy
argocd      infra-argocd                          OutOfSync     Healthy
argocd      infra-cert-manager                    Synced        Healthy
argocd      infra-gateway                         Synced        Healthy
argocd      infra-gateway-redirect                Synced        Healthy
argocd      infra-kubelet-serving-cert-approver   Synced        Healthy
argocd      infra-proxmox-csi                     Synced        Healthy
argocd      root                                  Synced        Healthy
```

### get sync status

```
k get -n argocd applications app-adguard -o yaml | yq '.status | pick(["health", "sync", "conditions"])'
```

#### Example Output

```yaml
health:
  lastTransitionTime: "2026-02-23T18:40:43Z"
  status: Healthy
sync:
  comparedTo:
    destination:
      namespace: adguard
      server: https://kubernetes.default.svc
    source:
      path: k8s/apps/dns/adguard/envs/prod
      repoURL: https://github.com/isejalabs/homelab.git
      targetRevision: HEAD
  revision: d9b315082ae65b874c84ebce8f7d74f9682e81f2
  status: Synced
```

## Configuration
### Admin Password

```sh
kubectl -n argocd get secret argocd-initial-admin-secret -ojson | jq -r ' .data.password | @base64d'
```

### Resource Limits
#### Memory

| Component           | Mem Usage Q/P | Request | Limit | New Req | New Limit |
| ------------------- | ------------- | ------- | ----- | ------- | --------- |
| appl-controller     | 250 / 188     | 512     | 2G    | 256     | 512       |
| appl.set-controller | 26 / 34       | 256     | 1024  | 128     | 256       |
| redis               | 5 / 4         | 0       | 0     | 8       | 64        |
| repo-server         | 62 / 33       | 512     | 2G    | 128     | 256       |
| server              | 174 / 29      | 256     | 1024  | 256     | 512       |

