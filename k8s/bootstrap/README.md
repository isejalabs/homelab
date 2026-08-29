## Stages of bootstrapping

Bootstrapping the cluster is done in 3 stages by different tools:

1. Terragrunt is used to provision the VMs in Proxmox and install Talos OS Kubernetes distribution.
1. Helmfile is used to 
   - install some crucial CRDs in the cluster,
   - install foundational infrastructure apps in the cluster (e.g. cilium CNI, secrets controller, cert-manager, flux).
1. Afterwards, Flux CD will automatically reconcile with the Git repository to install all remaining apps in the cluster.

## Deploying infrastructure and applications

> [!TIP]
> Substitute `<env>` (or the example environment `dev`) with the specific environment, e.g. `dev`, `qa`, `prod`
>
> In the following, the command `k` is aliased for `kubectl` (`alias k=kubectl`)

Once the cluster is bootstrapped with terragrunt, the infrastructure and applications can be deployed.

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

## Automatic bootstrapping by Helmfile and FluxCD

The cluster can be bootstrapped only automatically by leveraging [`helmfile`](https://helmfile.readthedocs.io/en/latest/) and [Flux CD](https://fluxcd.io/).

### Helmfile

#### Install CRDs in the cluster

Run the following command to install crucial CRDs in the cluster in the `<env>` environment:

```sh
helmfile -f k8s/bootstrap/helmfile/crds -e <env> template -q | \
  yq ea -r -e 'select(.kind == "CustomResourceDefinition")' | \
  kubectl apply --server-side --force-conflicts -f -
```

For example, the following command will install CRDs in the `rebuild` environment:

```sh
helmfile -f k8s/bootstrap/helmfile/crds -e rebuild template -q | yq ea -r -e 'select(.kind == "CustomResourceDefinition")' | kubectl apply --server-side --force-conflicts -f -
```

Output of the command will look like this:

```text
❯ helmfile -f k8s/bootstrap/helmfile/crds -e rebuild template -q | yq ea -r -e 'select(.kind == "CustomResourceDefinition")' | kubectl apply --server-side --force-conflicts -f -
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
```

#### Install apps in the cluster

Run the following command to bootstrap the cluster in the `<env>` environment:

```sh
helmfile -f k8s/bootstrap/helmfile/apps -e <env> sync --hide-notes
```

For example, the following command will bootstrap the cluster in the `rebuild` environment:

```sh
helmfile -f k8s/bootstrap/helmfile/apps -e rebuild sync --hide-notes
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
