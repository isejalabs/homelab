# ToDo

- [ ] document folder structure
- [X] document bootstrap process (incl. manual steps and automation via CI/CD pipelines)
- [ ] document kustomize overlay approach (incl. transformers and components)

# Bootstrapping the cluster and deploying applications

> [!TIP]
> Substitute `<env>` (or the example environment `dev`) with the specific environment, e.g. dev, qa, prod
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

Check that all nodes and pods are up running:

```sh
kubectl get nodes -A -o wide
kubectl get pods -A -o wide
```

Check for failed pods:

```sh
kubectl get pods -A --field-selector=status.phase=Failed

# alternatively, check for non-running pods (e.g. pending, crashloopbackoff, etc.)
# this will also reveal "completed" pods whigh are not running anymore but have completed successfully
# "completed" pods can be expected for some workloads, e.g. jobs for cilium installation, cert-manager jobs)
kubectl get pods -A --field-selector=status.phase!=Running
```

## Bootstrapping options

The cluster can be bootstrapped in two ways:

1. [**Manual bootstrapping**](#manual-bootstrapping) by applying the manifests with `kubectl apply -k` or `kustomize build --enable-helm | kubectl apply`, subsequently for the `core`, `infra` and `apps` categories, as described in the following sections. This approach is more error-prone and requires more manual work, but it allows for a better understanding of the bootstrapping process and the dependencies between the different components.
2. [**Automatic bootstrapping**](#automatic-bootstrapping-via-argocd) via ArgoCD, by applying the ArgoCD application manifests and letting ArgoCD take care of the rest of the bootstrapping process, as it will automatically apply the manifests for the `core`, `infra` and `apps` categories.

# Automatic bootstrapping via ArgoCD

The ArgoCD application manifests are located in the `k8s/infra/controller/argocd/` folder. The `base` folder contains the base application manifests, which are environment-agnostic, while the `envs` folder contains the environment-specific application manifests, which are applied on top of the base manifests. 

You can apply the ArgoCD application manifests with the following command:

```sh
kustomize build --enable-helm k8s/infra/controller/argocd/envs/<env> | kubectl apply -f - --server-side
```

For example, the following command will bootstrap the cluster in the `rebuild` environment:

```sh
kustomize build --enable-helm k8s/infra/controller/argocd/envs/rebuild | kaf - --server-side --context admin@rebuild-homelab
```

Automatic bootstrapping via ArgoCD is the recommended approach for the following environments:

- prod
- qa
- rebuild
- head

# Manual bootstrapping

You need to bootstrap the cluster in the following order, as there are dependencies between the different components:

1. [**Core**](#core-requirements): The core components are the foundation of the cluster and need to be up and running before you can deploy any other components, e.g. the CNI needs to be up and running before you can deploy the Gateway API controller, as the latter depends on the CNI for networking.
2. [**Infrastructure**](#infrastructure): The infrastructure components are the building blocks for the applications and need to be up and running before you can deploy any applications, e.g. the cert-manager needs to be up and running before you can deploy any certificates or issuers, as they depend on the cert-manager for certificate management.
3. [**Applications**](#applications): The applications are the actual workloads that run on the cluster and depend on the core and infrastructure components to be up available.

## Core Requirements

The `core` set covers depencencies necessary even for `infra` components, e.g.

- CNI (cilium), incl. BGP configuration
- Gateway API - CRDs only (controller in `infra` set, as it depends on CNI being up and running)
- Sealed Secrets Controller (secret management for infra components)

### Set

Use the `kustomize` set in the `_envs` folder for deploying all applications in the `core` category.

```sh
# deploy for current context (retrieves "dev" environment out of "admin@dev-homelab" automatically)
kustomize build --enable-helm k8s/core/_envs/$(kubectl config current-context | cut -d "@" -f 2 | cut -d "-" -f 1) | kubectl apply -f -

# alternatively, deploy for environment `dev` explicitely (be sure to have the correct context active, e.g. `admin@dev-homelab`)
kustomize build --enable-helm k8s/core/_envs/dev | kubectl apply -f -
```

### Need to run multiple times

> [!Important]
> You will need to run the above command multiple times, as some resources depend on each other.

The Cilium BGP CRDs need to be available before the BGP configuration can be applied successfully. Thus, you will need to run the above command multiple times, at minimum twice, to get everything up and running.
If you get an error about the BGP CRDs not being found (note the "ensure CRDs are installed first" below), just run the command again after a while, as the Cilium operator will create the CRDs once it is up and running:

```text
resource mapping not found for name: "bgp-advertisements" namespace: "" from "STDIN": no matches for kind "CiliumBGPAdvertisement" in version "cilium.io/v2"
ensure CRDs are installed first
resource mapping not found for name: "cilium-bgp" namespace: "" from "STDIN": no matches for kind "CiliumBGPClusterConfig" in version "cilium.io/v2"
ensure CRDs are installed first
ciliumloadbalancerippool.cilium.io/bgp-pool created
resource mapping not found for name: "cilium-peer" namespace: "" from "STDIN": no matches for kind "CiliumBGPPeerConfig" in version "cilium.io/v2"
ensure CRDs are installed first
```

The CNI is running properly when you see the following output for the `cilium status` command:

```sh
❯ cilium status --wait
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
 \__/¯¯\__/    Hubble Relay:       OK
    \__/       ClusterMesh:        disabled
...
``` 

... and the BGP configuration is applied successfully, when you see the following output for the `kubectl apply` command (note the "created" or "unchanged" status):

```text
ciliumbgpadvertisement.cilium.io/bgp-advertisements created
ciliumbgpclusterconfig.cilium.io/cilium-bgp created
ciliumbgppeerconfig.cilium.io/cilium-peer created
ciliumloadbalancerippool.cilium.io/bgp-pool unchanged
```

This will be reflected in the output of `cilium bgp status`:

```sh
❯ k get ciliumbgppeerconfigs
NAME          AGE
cilium-peer   1m
```


Alternatively to the `cilium` command, you can check for the CNI being ready by checking the status of the cilium pods in the `kube-system` namespace.

```sh
k get pods -n kube-system -l k8s-app=cilium
```

You will need to wait for the CNI to be up and running before you can deploy other applications, e.g. the Gateway API controller.

### Handling individual applications

If not all applications are needed, use the following `kustomize build` commands instead.

#### Cilium

```sh
kustomize build --enable-helm k8s/core/network/cilium/envs/dev | kubectl apply -f -
```

##### Checks

Check for cilium being deployed successfully:

```sh
cilium status --wait
```

##### Configuration

Print out configuration:

```sh
kubectl -n kube-system get configmap cilium-config -o yaml

# alternatively
helm get values cilium -n kube-system
```

#### Gateway API

```sh
kustomize build --enable-helm k8s/core/network/gateway/envs/<env> | kubectl apply -f -
```

#### Sealed Secrets

```sh
kustomize build --enable-helm infra/controllers/sealed-secrets | kubectl apply -f -
```

##### Usage

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

##### Decrypt

```sh
k get secrets -n sealed-secrets -o yaml > sealed-secrets-key.yaml
```

## Infrastructure

### Set

Use the `kustomize` set for deploying all applications in the `infra` category.

```sh
kustomize build --enable-helm k8s/infra/_envs/dev | kubectl apply -f -
```

### Need to run multiple times

> [!Important]
> You will need to run the above command **two times**.

Some resources depend on each other, e.g. the cert-manager controller needs to be up and running before you can apply the certificate and issuer resources. If you get an error about the CRDs not being found (cf. below), just run the command again after a while, as the cert-manager operator will create the CRDs once it is up and running:

```
resource mapping not found for name: "cert" namespace: "gateway" from "STDIN": no matches for kind "Certificate" in version "cert-manager.io/v1"
ensure CRDs are installed first
resource mapping not found for name: "cloudflare-cluster-issuer" namespace: "" from "STDIN": no matches for kind "ClusterIssuer" in version "cert-manager.io/v1"
ensure CRDs are installed first
```

You can check for the cert-manager being up and running by checking the status of the cert-manager pods in the `cert-manager` namespace.

```sh
k get pods -n cert-manager
```

You can also check the for the certificate beging issued successfully by checking the status of the certificate resource:

```sh
❯ k get certificate -n gateway
NAME   READY   SECRET   AGE
cert   True    cert     1m
```

### Handling individual applications

If not all applications are needed, use the following `kustomize build` commands instead.

### Cert Manager

```sh
k describe -n cert-manager secrets

k logs -n cert-manager services/cert-manager -f

k get secrets -n cert-manager cloudflare-api-token -o json | jq -r '.data."api-token" | @base64d'
```

#### Proxmox CSI

```sh
kustomize build --enable-helm infra/storage/proxmox-csi | kubectl apply -f -
```

Check for Proxmox CSI being connected with Proxmox server properly:

> [!TIP] **TODO**: Command does not provide output initially. Maybe only after first app deployment?

```sh
kubectl get csistoragecapacities -ocustom-columns=CLASS:.storageClassName,AVAIL:.capacity,ZONE:.nodeTopology.matchLabels -A
k get -A pv
```

## Applications

### Handling individual applications

#### whoami

```sh
kustomize build --enable-helm k8s/apps/diag/whoami/envs/<env> | kubectl apply -f -
```
