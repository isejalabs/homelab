# ToDo

- [ ] document folder structure
- [ ] document kustomize overlay approach (incl. transformers and components)

# Manual bootstrap

> **Note**: Substitute `<env>` with the specific environment, e.g. dev, qa, prod
> <br>
> In the following the command `k` is aliased for `kubectl` (`alias k=kubectl`)

## Preliminary Checks

Check cluster is reachable and you can authenticate.

```sh
k config get-contexts
k config current-context

# change active context
k config use-context admin@foo

# execute a command for a specific context using --context param
k get all -A --context admin@bar
```

Check that all nodes and pods ar up running

```sh
kubectl get nodes -A -o wide
kubectl get pods -A -o wide
```

## Core Requirements

The `core` set covers depencencies necessary even for `infra` components, e.g.

- CNI (cilium)
- Gateway API - CRDs only
- Sealed Secrets Controller

### Set

Use the set for deploying all applications in the `core` category.

```sh
kustomize build --enable-helm k8s/core/_envs/dev | kubectl apply -f -
```

If not all applications are needed, use the following `kustomize build` commands instead.

### Cilium

```sh
kustomize build --enable-helm k8s/core/network/cilium/envs/dev | kubectl apply -f -
```

#### Checks

Check for cilium being deployed successfully:

```sh
cilium status --wait
```

#### Configuration

Print out configuration:

```sh
kubectl -n kube-system get configmap cilium-config -o yaml

# alternatively
helm get values cilium -n kube-system
```

### Gateway API

```sh
kustomize build --enable-helm k8s/core/network/gateway/envs/<env> | kubectl apply -f -
```

### Sealed Secrets

```sh
kustomize build --enable-helm infra/controllers/sealed-secrets | kubectl apply -f -
```

#### Usage

Check whether Sealed Secrets Controller is working (you need to have `kubeseal` CLI installed on the workstation as well):

```sh
echo -n mytestsecret | kubectl create secret generic mysecretname --dry-run=client --from-file=mykey=/dev/stdin -o yaml | kubeseal --controller-namespace sealed-secrets -o yaml -n mynamespace
```

```yaml
---
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  creationTimestamp: null
  name: mysecretname
  namespace: mynamespace
spec:
  encryptedData:
    mykey: AgB/MAdkSJEnRDIlxxQ8cfcRNKqf1fFVzNLigAuv4L91tWDF4qaUHVtkZANyqBJEI4iVOt9Luk2o90dY7dZVyK3X3VBh1v9FZScUl/9jxnlGp0VMT4PIMf4HPEPRGHYcEcDovN1kaw5Y/a64hPORneIBRl6vuiT2OeuuI2ik4PlNNUaX4F1cbKz1ltbnZ+r2Lcwvwwfp0mVA6Ust5WBNCD76ZozGH19p7xAV4FEdjeTpmZ9wVl9lj1AWIVdxVEluoRK5zi2Q2fVYBG0+sXGa1erayP5egw3muFT6sW1degGEAtYosH4L2zhKa+VL7rdX5iGAgXrDWkas3MtgTe0ZmP5oCiCg4cq0kLXQ7x5dXpCVql3to7tvNcy5Pd1IncBInqw7YLvTzM2uIk673/gRvcfokSL6pvDEc+nROz5HX3OAXc1zjykxgO3FTRCOi++E283XtmalPP4sj8R0RgHqbt9qG3UhvyhX2MXFyONHV3V88b8kTi5a44bmZ4mwZ/7paMRyPnYt+Hg94kyRvCk2CUzLBZJrNlzJOGV+zAy4Kr0yE0jueNkjSeQZUj30aw4bn78Pnqc1BhgN/wtKMPT/VipMf3OwcV+1s9SrbuSNJpvIs/RWHg9MSb9gT5A9eLnOP36dD4ksP/Vo0l/uP6aobNBxhG7V3Ss2oPXpmhAD3nBJsJecd3ECnd7bmsRdCweGhY9cuYmQCkLsYWgRC8I=
  template:
    metadata:
      creationTimestamp: null
      name: mysecretname
      namespace: mynamespace
```

Show existing sealed secrets:

```sh
k get sealedsecrets.bitnami.com -A
```

Encrypt and decrypt secrets per:

> Note the preceding blank space before some of the commands in order to prevent the command from being recorded in the shell's history.

```sh
echo -n bar | kubectl create secret generic mysecret --dry-run=client --from-file=foo=/dev/stdin -o yaml >mysecret.yaml

 echo -n test2 | kubectl create secret generic cloudflare-api-token --dry-run=client --from-file=api-token=/dev/stdin -o yaml | kubeseal --controller-namespace sealed-secrets -o yaml -n cert-manager --merge-into infra/controllers/cert-manager/cloudflare-api-token.yaml
 echo -n my-tunnel-secret | kubectl create secret generic tunnel-credentials --dry-run=client --from-file=credentials.json=/dev/stdin -o yaml | kubeseal --controller-namespace sealed-secrets -o yaml -n cloudflared --merge-into infra/network/cloudflared/tunnel-credentials.yaml
 cat ~/.cloudflared/da8acdd7-2646-4d2b-bec5-c147b03c05fa.json | kubectl create secret generic tunnel-credentials --dry-run=client --from-file=credentials.json=/dev/stdin -o yaml | kubeseal --controller-namespace sealed-secrets -o yaml -n cloudflared --merge-into ~/src/vehagn-homelab/k8s/infra/network/cloudflared/tunnel-credentials.yaml

cat users.yaml | kubectl create secret generic users --dry-run=client --from-file=users.yaml=/dev/stdin -o yaml | kubeseal --controller-namespace sealed-secrets -o yaml -n dns --merge-into infra/network/dns/adguard/secret-users.yaml

# test
kubeseal --controller-name=sealed-secrets --controller-namespace=sealed-secrets < infra/controllers/cert-manager/cloudflare-api-token.yaml --recovery-unseal --recovery-private-key sealed-secrets-key.yaml -o json | jq -r ' .data."api-token" | @base64d'
```

#### Decrypt

```sh
k get secrets -n sealed-secrets -o yaml > sealed-secrets-key.yaml


```

## Infrastructure

### Set

Use the set for deploying all applications in the `infra` category.

```sh
kustomize build --enable-helm k8s/infra/_envs/dev | kubectl apply -f -
```

If not all applications are needed, use the following `kustomize build` commands instead.

### Cert Manager

```sh
k describe -n cert-manager secrets

k logs -n cert-manager services/cert-manager -f

k get secrets -n cert-manager cloudflare-api-token -o json | jq -r '.data."api-token" | @base64d'
```

### Proxmox CSI

```sh
kustomize build --enable-helm infra/storage/proxmox-csi | kubectl apply -f -
```

> **TODO**: Command does not provide output initially. Maybe only after first app deployment?

Check for Proxmox CSI being connected with Proxmox server properly:

```sh
kubectl get csistoragecapacities -ocustom-columns=CLASS:.storageClassName,AVAIL:.capacity,ZONE:.nodeTopology.matchLabels -A
k get -A pv
```

## Applications

## Example: whoami

```sh
kustomize build --enable-helm k8s/apps/diag/whoami/envs/<env> | kubectl apply -f -
```
