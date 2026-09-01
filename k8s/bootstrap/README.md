# Bootstrapping the cluster

## Stages of bootstrapping

Bootstrapping the cluster is done in 3 phases:

1. **`terragrunt`** is used to **provision the VMs in Proxmox** and **install Talos OS** Kubernetes distribution.
1. **`just`** is used to **deploy the cluster** by leveraging `helmfile` to install
   - some **crucial CRDs**,
   - **foundational infrastructure apps** (e.g. cilium CNI, secrets controller, cert-manager, flux).

   in the cluster.
1. Afterwards, **Flux CD** will automatically reconcile with the Git repository to install some further infrastructure components (e.g. CSI) and all application workloads in the cluster.

This document describes the steps to bootstrap the cluster by using `just`.

## Provision VMs and install Talos OS Kubernetes distribution by using Terragrunt

Provisioning the VMs in Proxmox and installing Talos OS Kubernetes distribution is done by using Terragrunt.  The steps are described in the [README](../../terragrunt/README.md) of the `terragrunt/` directory of this repository.

## Deploying infrastructure and applications

Once the Talos OS VMs are provisioned with terragrunt, the infrastructure and applications can be deployed to the cluster.  The entire process is driven by using [just](https://github.com/casey/just).  It is a command runner similar to `make`.

Before running the `just` command, make sure that the initial cluster is ready and you have access to the cluster and .

### Preliminary Checks

> [!TIP]
> Substitute `<env>` (or the example environment `dev`) with the specific environment, e.g. `dev`, `qa`, `prod`
>
> In the following, the command `k` is aliased for `kubectl` (`alias k=kubectl`)

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

### Cluster deployment with `just` (and Flux CD)

The cluster can be easily bootstrapped by using the `just` command by also stating the environment to bootstrap the cluster for (`-e <env>` or `--env <env>`):

```sh
just bootstrap::cluster --env <env>
```

The following example command will bootstrap the cluster in the `rebuild` environment, after your confirmation:

```sh
just bootstrap::cluster --env rebuild
```

Output of the command will look like this:

```
❯ just bootstrap cluster --env rebuild
Bootstrap cluster for environment "rebuild"? [y|N] y
...
============================================== Updated Releases ===============================================
NAME             NAMESPACE        CHART                                                      VERSION   DURATION
cilium           kube-system      oci://quay.io/cilium/charts/cilium                         1.18.13      3m56s
sealed-secrets   sealed-secrets   oci://registry-1.docker.io/bitnamicharts/sealed-secrets    2.19.3         50s
cert-manager     cert-manager     oci://quay.io/jetstack/charts/cert-manager                 v1.21.1        28s
flux-operator    flux-system      oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator   0.59.0         21s
flux-instance    flux-system      oci://ghcr.io/controlplaneio-fluxcd/charts/flux-instance   0.59.0         27s

2026-09-01T18:57:04+02:00 INFO Deployed cluster env=rebuild
just bootstrap cluster --env rebuild  6,59s user 2,29s system 2% cpu 6:15,81 total
```


<details>
<summary>Full version:</summary>

```
❯ just bootstrap cluster --env rebuild
Bootstrap cluster for environment "rebuild"? [y|N] y
2026-09-01T18:50:51+02:00 INFO Running stage... stage=core
customresourcedefinition.apiextensions.k8s.io/grafanaalertrulegroups.grafana.integreatly.org serverside-applied
customresourcedefinition.apiextensions.k8s.io/grafanacontactpoints.grafana.integreatly.org serverside-applied
customresourcedefinition.apiextensions.k8s.io/grafanadashboards.grafana.integreatly.org serverside-applied
customresourcedefinition.apiextensions.k8s.io/grafanadatasources.grafana.integreatly.org serverside-applied
customresourcedefinition.apiextensions.k8s.io/grafanafolders.grafana.integreatly.org serverside-applied
customresourcedefinition.apiextensions.k8s.io/grafanalibrarypanels.grafana.integreatly.org serverside-applied
customresourcedefinition.apiextensions.k8s.io/grafanamanifests.grafana.integreatly.org serverside-applied
customresourcedefinition.apiextensions.k8s.io/grafanamutetimings.grafana.integreatly.org serverside-applied
customresourcedefinition.apiextensions.k8s.io/grafananotificationpolicies.grafana.integreatly.org serverside-applied
customresourcedefinition.apiextensions.k8s.io/grafananotificationpolicyroutes.grafana.integreatly.org serverside-applied
customresourcedefinition.apiextensions.k8s.io/grafananotificationtemplates.grafana.integreatly.org serverside-applied
customresourcedefinition.apiextensions.k8s.io/grafanas.grafana.integreatly.org serverside-applied
customresourcedefinition.apiextensions.k8s.io/grafanaserviceaccounts.grafana.integreatly.org serverside-applied
customresourcedefinition.apiextensions.k8s.io/alertmanagerconfigs.monitoring.coreos.com serverside-applied
customresourcedefinition.apiextensions.k8s.io/alertmanagers.monitoring.coreos.com serverside-applied
customresourcedefinition.apiextensions.k8s.io/podmonitors.monitoring.coreos.com serverside-applied
customresourcedefinition.apiextensions.k8s.io/probes.monitoring.coreos.com serverside-applied
customresourcedefinition.apiextensions.k8s.io/prometheusagents.monitoring.coreos.com serverside-applied
customresourcedefinition.apiextensions.k8s.io/prometheuses.monitoring.coreos.com serverside-applied
customresourcedefinition.apiextensions.k8s.io/prometheusrules.monitoring.coreos.com serverside-applied
customresourcedefinition.apiextensions.k8s.io/scrapeconfigs.monitoring.coreos.com serverside-applied
customresourcedefinition.apiextensions.k8s.io/servicemonitors.monitoring.coreos.com serverside-applied
customresourcedefinition.apiextensions.k8s.io/thanosrulers.monitoring.coreos.com serverside-applied
2026-09-01T18:51:01+02:00 INFO Running stage... stage=apps
Pulling ghcr.io/controlplaneio-fluxcd/charts/flux-instance:0.59.0
Pulling ghcr.io/controlplaneio-fluxcd/charts/flux-operator:0.59.0
Skipping refresh for chart at /Users/sebi/Library/Caches/helmfile/oci__registry-1_docker_io/bitnamicharts/sealed-secrets/2.19.3 (shared cache, another process may be using it; run 'helmfile cache cleanup' to force refresh)
Skipping refresh for chart at /Users/sebi/Library/Caches/helmfile/oci__quay_io/jetstack/charts/cert-manager/v1.21.1 (shared cache, another process may be using it; run 'helmfile cache cleanup' to force refresh)
Skipping refresh for chart at /Users/sebi/Library/Caches/helmfile/oci__quay_io/cilium/charts/cilium/1.18.13 (shared cache, another process may be using it; run 'helmfile cache cleanup' to force refresh)
Pulled: ghcr.io/controlplaneio-fluxcd/charts/flux-instance:0.59.0
Digest: sha256:c7078e69a189182c0f89e0d48bdfefd4f86f84bea7d4e842eba38bd8c12d2980
Pulled: ghcr.io/controlplaneio-fluxcd/charts/flux-operator:0.59.0
Digest: sha256:ae962f87e04301c61aeb41698146027ba4c2e4b4157d4c08fb4a4e335be9aa42
Upgrading release=cilium, chart=/Users/sebi/Library/Caches/helmfile/oci__quay_io/cilium/charts/cilium/1.18.13/cilium, namespace=kube-system
Release "cilium" has been upgraded. Happy Helming!
NAME: cilium
LAST DEPLOYED: Tue Sep  1 18:51:02 2026
NAMESPACE: kube-system
STATUS: deployed
REVISION: 2
DESCRIPTION: Upgrade complete
TEST SUITE: None
Listing releases matching ^cilium$
cilium	kube-system	2       	2026-09-01 18:51:02.891197 +0200 CEST	deployed	cilium-1.18.13	1.18.13

hook[postsync] logs | customresourcedefinition.apiextensions.k8s.io/ciliumbgpadvertisements.cilium.io condition met
hook[postsync] logs | customresourcedefinition.apiextensions.k8s.io/ciliumbgpclusterconfigs.cilium.io condition met
hook[postsync] logs | customresourcedefinition.apiextensions.k8s.io/ciliumbgppeerconfigs.cilium.io condition met
hook[postsync] logs | customresourcedefinition.apiextensions.k8s.io/ciliumloadbalancerippools.cilium.io condition met
hook[postsync] logs |
Upgrading release=sealed-secrets, chart=/Users/sebi/Library/Caches/helmfile/oci__registry-1_docker_io/bitnamicharts/sealed-secrets/2.19.3/sealed-secrets, namespace=sealed-secrets
Release "sealed-secrets" does not exist. Installing it now.
NAME: sealed-secrets
LAST DEPLOYED: Tue Sep  1 18:54:58 2026
NAMESPACE: sealed-secrets
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE: None
Listing releases matching ^sealed-secrets$
sealed-secrets	sealed-secrets	1       	2026-09-01 18:54:58.822408 +0200 CEST	deployed	sealed-secrets-2.19.3	0.39.1
Upgrading release=cert-manager, chart=/Users/sebi/Library/Caches/helmfile/oci__quay_io/jetstack/charts/cert-manager/v1.21.1/cert-manager, namespace=cert-manager
Release "cert-manager" does not exist. Installing it now.
NAME: cert-manager
LAST DEPLOYED: Tue Sep  1 18:55:49 2026
NAMESPACE: cert-manager
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE: None
Listing releases matching ^cert-manager$
cert-manager	cert-manager	1       	2026-09-01 18:55:49.036471 +0200 CEST	deployed	cert-manager-v1.21.1	v1.21.1
Upgrading release=flux-operator, chart=/Users/sebi/Library/Caches/helmfile/oci__ghcr_io/controlplaneio-fluxcd/charts/flux-operator/0.59.0/flux-operator, namespace=flux-system
Release "flux-operator" does not exist. Installing it now.
NAME: flux-operator
LAST DEPLOYED: Tue Sep  1 18:56:16 2026
NAMESPACE: flux-system
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE: None
Listing releases matching ^flux-operator$
flux-operator	flux-system	1       	2026-09-01 18:56:16.755728 +0200 CEST	deployed	flux-operator-0.59.0	v0.59.0
Upgrading release=flux-instance, chart=/Users/sebi/Library/Caches/helmfile/oci__ghcr_io/controlplaneio-fluxcd/charts/flux-instance/0.59.0/flux-instance, namespace=flux-system
Release "flux-instance" does not exist. Installing it now.
NAME: flux-instance
LAST DEPLOYED: Tue Sep  1 18:56:37 2026
NAMESPACE: flux-system
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE: None
Listing releases matching ^flux-instance$
flux-instance	flux-system	1       	2026-09-01 18:56:37.740107 +0200 CEST	deployed	flux-instance-0.59.0	v0.59.0

============================================== Updated Releases ===============================================
NAME             NAMESPACE        CHART                                                      VERSION   DURATION
cilium           kube-system      oci://quay.io/cilium/charts/cilium                         1.18.13      3m56s
sealed-secrets   sealed-secrets   oci://registry-1.docker.io/bitnamicharts/sealed-secrets    2.19.3         50s
cert-manager     cert-manager     oci://quay.io/jetstack/charts/cert-manager                 v1.21.1        28s
flux-operator    flux-system      oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator   0.59.0         21s
flux-instance    flux-system      oci://ghcr.io/controlplaneio-fluxcd/charts/flux-instance   0.59.0         27s

2026-09-01T18:57:04+02:00 INFO Deployed cluster env=rebuild
just bootstrap cluster --env rebuild  6,59s user 2,29s system 2% cpu 6:15,81 total
```

</details>

> [!NOTE]
> What's happening behind the scenes:
> 1. The `just` command will just call `helmfile`, which is a tool to manage multiple Helm charts.  The `helmfile` tool is used to 
>    - install some crucial **CRDs** in the cluster by extracting them from the Helm charts and applying them manually with `kubectl`,
>    - install **foundational infrastructure apps** in the cluster (e.g. cilium CNI, secrets controller, cert-manager, flux).
> 1. Afterwards, **Flux CD** will automatically reconcile with the Git repository to install some further infrastructure as well as **all apps in the cluster**.
>
> Actually, it would be sufficient only installing Flux CD to the cluster (and CNI cilium which is installed by terragrunt already).  However, installing some CRDs and foundational infrastructure components beforehand is done to avoid issues with Helm chart installations that require CRDs to be present before the Helm chart can be installed and getting around complex dependency chains in Flux.

### Flux CD

You can check the status of cluster bootstrapping by flux by running the `flux` command:

```sh
flux get ks -A
```

Output of the command will look like this:

```
❯ flux get ks -A
NAMESPACE  	NAME                   	REVISION                     	SUSPENDED	READY	MESSAGE
flux-system	actualbudget           	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	adguard                	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	cert-manager           	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	checkmk-kube-agent     	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	cilium                 	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	flux-instance          	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	flux-operator          	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	flux-system            	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	gateway-api            	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	gateway-api-crds       	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	gateway-api-redirect   	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	infra-ns               	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	k-serving-cert-approver	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	longhorn               	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	longhorn-core          	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	metrics-server         	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	proxmox-csi            	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	sealed-secrets         	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	unbound                	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	unifi-controller       	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
flux-system	whoami                 	refs/heads/main@sha1:d50cc11a	False    	True 	Applied revision: refs/heads/main@sha1:d50cc11a
```
