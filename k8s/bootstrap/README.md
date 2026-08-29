## Bootstrapping the cluster and deploying applications

> [!TIP]
> Substitute `<env>` (or the example environment `dev`) with the specific environment, e.g. dev, qa, prod
>
> In the following the command `k` is aliased for `kubectl` (`alias k=kubectl`)

### Preliminary Checks

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

### Bootstrapping options

The cluster needs to get bootstrapped with FluxCD. It cannot _easily_ get bootstrapped manually as the Kubernetes manifests depend on FluxCD. Especially, for Helm charts, Flux's `HelmRelease` (and `HelmRepository` and `OCIRepository`) manifests are used instead of `kustomize`'s `HelmChart` and `HelmChartInflationGenerator` features. Thus, Flux's `HelmController` needs to be up and running before any Helm charts can be deployed.

There is a possibility to bootstrap the cluster manually by deploying the manifests with `kubectl apply -k` or `kustomize build | kubectl apply`, but this is not recommended.

The bootstrapping process is described in the following sections.

The cluster can be bootstrapped in two ways:

1. [**Automatic bootstrapping**](#automatic-bootstrapping-via-argocd) via FluxCD, by applying the FluxCD application manifests and letting FluxCD take care of the rest of the bootstrapping process, as it will automatically apply the manifests for the `core`, `infra` and `apps` categories and manage inter-app dependencies.
1. **Not recommended**: [**Manual bootstrapping**](#manual-bootstrapping) by applying the manifests with `kubectl apply -k` or `kustomize build | kubectl apply`, subsequently for the `core`, `infra` and `apps` categories, as described in the following sections. This approach is more error-prone and requires more manual work, but it allows for a better understanding of the bootstrapping process and the dependencies between the different components.

> [!TIP]
> Applying manifests manually, especially in the application category, allows adding and configuring new applications before committing the changes to the Git repository yet.

## Automatic bootstrapping by Helmfile and FluxCD

Among the options for bootstrapping FluxCD, the approach of installing `flux-operator` and `flux-instance` is doing it via **Helmfile**.

Run the following command to bootstrap the cluster in the `<env>` environment:

```sh
helmfile -f k8s/bootstrap/helmfile -e <env> sync --hide-notes
```

For example, the following command will bootstrap the cluster in the `rebuild` environment:

```sh
helmfile -f k8s/bootstrap/helmfile -e rebuild sync --hide-notes
```

Output of the command will look like this:

```
...
============================================== Updated Releases ===============================================
NAME             NAMESPACE        CHART                                                      VERSION   DURATION
cilium           kube-system      oci://quay.io/cilium/charts/cilium                         1.18.13      2m27s
sealed-secrets   sealed-secrets   oci://registry-1.docker.io/bitnamicharts/sealed-secrets    2.19.3         12s
cert-manager     cert-manager     oci://quay.io/jetstack/charts/cert-manager                 v1.21.1        29s
flux-operator    flux-system      oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator   0.58.1         23s
flux-instance    flux-system      oci://ghcr.io/controlplaneio-fluxcd/charts/flux-instance   0.58.1         51s
```
