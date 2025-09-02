## Context
```sh
❯ k config use-context admin@prod-homelab
Switched to context "admin@prod-homelab".
```

## Core

### 1st run

```sh
❯ kustomize build --enable-helm k8s/core/\_envs/$(kubectl config current-context | cut -d "@" -f 2 | cut -d "-" -f 1) | kubectl apply -f -
Warning: resource namespaces/cilium-secrets is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
namespace/cilium-secrets configured
Warning: resource customresourcedefinitions/gatewayclasses.gateway.networking.k8s.io is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io configured
Warning: resource customresourcedefinitions/gateways.gateway.networking.k8s.io is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io configured
Warning: resource customresourcedefinitions/grpcroutes.gateway.networking.k8s.io is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
customresourcedefinition.apiextensions.k8s.io/grpcroutes.gateway.networking.k8s.io configured
Warning: resource customresourcedefinitions/httproutes.gateway.networking.k8s.io is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io configured
Warning: resource customresourcedefinitions/referencegrants.gateway.networking.k8s.io is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
customresourcedefinition.apiextensions.k8s.io/referencegrants.gateway.networking.k8s.io configured
customresourcedefinition.apiextensions.k8s.io/sealedsecrets.bitnami.com created
Warning: resource customresourcedefinitions/tlsroutes.gateway.networking.k8s.io is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
customresourcedefinition.apiextensions.k8s.io/tlsroutes.gateway.networking.k8s.io configured
Warning: resource serviceaccounts/cilium is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
serviceaccount/cilium configured
Warning: resource serviceaccounts/cilium-envoy is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
serviceaccount/cilium-envoy configured
Warning: resource serviceaccounts/cilium-operator is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
serviceaccount/cilium-operator configured
Warning: resource serviceaccounts/hubble-relay is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
serviceaccount/hubble-relay configured
Warning: resource serviceaccounts/hubble-ui is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
serviceaccount/hubble-ui configured
serviceaccount/sealed-secrets-controller created
Warning: resource roles/cilium-gateway-secrets is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
role.rbac.authorization.k8s.io/cilium-gateway-secrets configured
Warning: resource roles/cilium-operator-gateway-secrets is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
role.rbac.authorization.k8s.io/cilium-operator-gateway-secrets configured
Warning: resource roles/cilium-operator-tlsinterception-secrets is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
role.rbac.authorization.k8s.io/cilium-operator-tlsinterception-secrets configured
Warning: resource roles/cilium-tlsinterception-secrets is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
role.rbac.authorization.k8s.io/cilium-tlsinterception-secrets configured
role.rbac.authorization.k8s.io/cilium-bgp-control-plane-secrets created
Warning: resource roles/cilium-config-agent is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
role.rbac.authorization.k8s.io/cilium-config-agent configured
role.rbac.authorization.k8s.io/sealed-secrets-controller-key-admin created
role.rbac.authorization.k8s.io/sealed-secrets-controller-service-proxier created
Warning: resource clusterroles/cilium is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
clusterrole.rbac.authorization.k8s.io/cilium configured
Warning: resource clusterroles/cilium-operator is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
clusterrole.rbac.authorization.k8s.io/cilium-operator configured
Warning: resource clusterroles/hubble-ui is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
clusterrole.rbac.authorization.k8s.io/hubble-ui configured
clusterrole.rbac.authorization.k8s.io/sealed-secrets-controller-unsealer created
Warning: resource rolebindings/cilium-gateway-secrets is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
rolebinding.rbac.authorization.k8s.io/cilium-gateway-secrets configured
Warning: resource rolebindings/cilium-operator-gateway-secrets is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
rolebinding.rbac.authorization.k8s.io/cilium-operator-gateway-secrets configured
Warning: resource rolebindings/cilium-operator-tlsinterception-secrets is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
rolebinding.rbac.authorization.k8s.io/cilium-operator-tlsinterception-secrets configured
Warning: resource rolebindings/cilium-tlsinterception-secrets is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
rolebinding.rbac.authorization.k8s.io/cilium-tlsinterception-secrets configured
rolebinding.rbac.authorization.k8s.io/cilium-bgp-control-plane-secrets created
Warning: resource rolebindings/cilium-config-agent is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
rolebinding.rbac.authorization.k8s.io/cilium-config-agent configured
rolebinding.rbac.authorization.k8s.io/sealed-secrets-controller-key-admin created
rolebinding.rbac.authorization.k8s.io/sealed-secrets-controller-service-proxier created
Warning: resource clusterrolebindings/cilium is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
clusterrolebinding.rbac.authorization.k8s.io/cilium configured
Warning: resource clusterrolebindings/cilium-operator is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
clusterrolebinding.rbac.authorization.k8s.io/cilium-operator configured
Warning: resource clusterrolebindings/hubble-ui is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
clusterrolebinding.rbac.authorization.k8s.io/hubble-ui configured
clusterrolebinding.rbac.authorization.k8s.io/sealed-secrets-controller-sealed-secrets created
Warning: resource configmaps/cilium-config is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
configmap/cilium-config configured
Warning: resource configmaps/cilium-envoy-config is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
configmap/cilium-envoy-config configured
Warning: resource configmaps/hubble-relay-config is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
configmap/hubble-relay-config configured
Warning: resource configmaps/hubble-ui-nginx is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
configmap/hubble-ui-nginx configured
Warning: resource secrets/cilium-ca is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
secret/cilium-ca configured
Warning: resource secrets/hubble-relay-client-certs is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
secret/hubble-relay-client-certs configured
Warning: resource secrets/hubble-server-certs is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
secret/hubble-server-certs configured
Warning: resource services/cilium-envoy is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
service/cilium-envoy configured
Warning: resource services/hubble-peer is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
service/hubble-peer configured
Warning: resource services/hubble-relay is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
service/hubble-relay configured
Warning: resource services/hubble-ui is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
service/hubble-ui configured
service/sealed-secrets-controller created
Warning: resource deployments/cilium-operator is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
deployment.apps/cilium-operator configured
Warning: resource deployments/hubble-relay is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
deployment.apps/hubble-relay configured
Warning: resource deployments/hubble-ui is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
deployment.apps/hubble-ui configured
deployment.apps/sealed-secrets-controller created
poddisruptionbudget.policy/sealed-secrets-controller created
Warning: resource daemonsets/cilium is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
daemonset.apps/cilium configured
Warning: resource daemonsets/cilium-envoy is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
daemonset.apps/cilium-envoy configured
ciliuml2announcementpolicy.cilium.io/default-l2-announcement-policy created
ciliumloadbalancerippool.cilium.io/bgp-pool created
resource mapping not found for name: "bgp-advertisements" namespace: "" from "STDIN": no matches for kind "CiliumBGPAdvertisement" in version "cilium.io/v2"
ensure CRDs are installed first
resource mapping not found for name: "cilium-bgp" namespace: "" from "STDIN": no matches for kind "CiliumBGPClusterConfig" in version "cilium.io/v2"
ensure CRDs are installed first
resource mapping not found for name: "cilium-peer" namespace: "" from "STDIN": no matches for kind "CiliumBGPPeerConfig" in version "cilium.io/v2"
ensure CRDs are installed first

```

### 2nd run

```sh
❯ kustomize build --enable-helm k8s/core/_envs/$(kubectl config current-context | cut -d "@" -f 2 | cut -d "-" -f 1) | kubectl apply -f -
namespace/cilium-secrets unchanged
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io configured
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io configured
customresourcedefinition.apiextensions.k8s.io/grpcroutes.gateway.networking.k8s.io configured
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io configured
customresourcedefinition.apiextensions.k8s.io/referencegrants.gateway.networking.k8s.io configured
customresourcedefinition.apiextensions.k8s.io/sealedsecrets.bitnami.com unchanged
customresourcedefinition.apiextensions.k8s.io/tlsroutes.gateway.networking.k8s.io configured
serviceaccount/cilium unchanged
serviceaccount/cilium-envoy unchanged
serviceaccount/cilium-operator unchanged
serviceaccount/hubble-relay unchanged
serviceaccount/hubble-ui unchanged
serviceaccount/sealed-secrets-controller unchanged
role.rbac.authorization.k8s.io/cilium-gateway-secrets unchanged
role.rbac.authorization.k8s.io/cilium-operator-gateway-secrets unchanged
role.rbac.authorization.k8s.io/cilium-operator-tlsinterception-secrets unchanged
role.rbac.authorization.k8s.io/cilium-tlsinterception-secrets unchanged
role.rbac.authorization.k8s.io/cilium-bgp-control-plane-secrets unchanged
role.rbac.authorization.k8s.io/cilium-config-agent unchanged
role.rbac.authorization.k8s.io/sealed-secrets-controller-key-admin unchanged
role.rbac.authorization.k8s.io/sealed-secrets-controller-service-proxier unchanged
clusterrole.rbac.authorization.k8s.io/cilium unchanged
clusterrole.rbac.authorization.k8s.io/cilium-operator unchanged
clusterrole.rbac.authorization.k8s.io/hubble-ui unchanged
clusterrole.rbac.authorization.k8s.io/sealed-secrets-controller-unsealer unchanged
rolebinding.rbac.authorization.k8s.io/cilium-gateway-secrets unchanged
rolebinding.rbac.authorization.k8s.io/cilium-operator-gateway-secrets unchanged
rolebinding.rbac.authorization.k8s.io/cilium-operator-tlsinterception-secrets unchanged
rolebinding.rbac.authorization.k8s.io/cilium-tlsinterception-secrets unchanged
rolebinding.rbac.authorization.k8s.io/cilium-bgp-control-plane-secrets unchanged
rolebinding.rbac.authorization.k8s.io/cilium-config-agent unchanged
rolebinding.rbac.authorization.k8s.io/sealed-secrets-controller-key-admin unchanged
rolebinding.rbac.authorization.k8s.io/sealed-secrets-controller-service-proxier unchanged
clusterrolebinding.rbac.authorization.k8s.io/cilium unchanged
clusterrolebinding.rbac.authorization.k8s.io/cilium-operator unchanged
clusterrolebinding.rbac.authorization.k8s.io/hubble-ui unchanged
clusterrolebinding.rbac.authorization.k8s.io/sealed-secrets-controller-sealed-secrets unchanged
configmap/cilium-config unchanged
configmap/cilium-envoy-config unchanged
configmap/hubble-relay-config unchanged
configmap/hubble-ui-nginx unchanged
secret/cilium-ca configured
secret/hubble-relay-client-certs configured
secret/hubble-server-certs configured
service/cilium-envoy unchanged
service/hubble-peer unchanged
service/hubble-relay unchanged
service/hubble-ui unchanged
service/sealed-secrets-controller configured
deployment.apps/cilium-operator configured
deployment.apps/hubble-relay configured
deployment.apps/hubble-ui configured
deployment.apps/sealed-secrets-controller configured
poddisruptionbudget.policy/sealed-secrets-controller configured
daemonset.apps/cilium configured
daemonset.apps/cilium-envoy configured
ciliumbgpadvertisement.cilium.io/bgp-advertisements created
ciliumbgpclusterconfig.cilium.io/cilium-bgp created
ciliumbgppeerconfig.cilium.io/cilium-peer created
ciliuml2announcementpolicy.cilium.io/default-l2-announcement-policy unchanged
ciliumloadbalancerippool.cilium.io/bgp-pool unchanged
```

## Infra

### 1st run

```sh
❯ kustomize build --enable-helm k8s/infra/\_envs/$(kubectl config current-context | cut -d "@" -f 2 | cut -d "-" -f 1) | kubectl apply -f -
namespace/cert-manager created
namespace/gateway created
storageclass.storage.k8s.io/proxmox-csi created
customresourcedefinition.apiextensions.k8s.io/certificaterequests.cert-manager.io created
customresourcedefinition.apiextensions.k8s.io/certificates.cert-manager.io created
customresourcedefinition.apiextensions.k8s.io/challenges.acme.cert-manager.io created
customresourcedefinition.apiextensions.k8s.io/clusterissuers.cert-manager.io created
customresourcedefinition.apiextensions.k8s.io/issuers.cert-manager.io created
customresourcedefinition.apiextensions.k8s.io/orders.acme.cert-manager.io created
serviceaccount/cert-manager created
serviceaccount/cert-manager-cainjector created
serviceaccount/cert-manager-startupapicheck created
serviceaccount/cert-manager-webhook created
serviceaccount/proxmox-csi-plugin-controller created
serviceaccount/proxmox-csi-plugin-node created
role.rbac.authorization.k8s.io/cert-manager-startupapicheck:create-cert created
role.rbac.authorization.k8s.io/cert-manager-tokenrequest created
role.rbac.authorization.k8s.io/cert-manager-webhook:dynamic-serving created
role.rbac.authorization.k8s.io/proxmox-csi-plugin-controller created
role.rbac.authorization.k8s.io/cert-manager-cainjector:leaderelection created
role.rbac.authorization.k8s.io/cert-manager:leaderelection created
clusterrole.rbac.authorization.k8s.io/proxmox-csi-plugin-controller created
clusterrole.rbac.authorization.k8s.io/proxmox-csi-plugin-node created
clusterrole.rbac.authorization.k8s.io/cert-manager-cainjector created
clusterrole.rbac.authorization.k8s.io/cert-manager-cluster-view created
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-approve:cert-manager-io created
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-certificates created
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-certificatesigningrequests created
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-challenges created
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-clusterissuers created
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-ingress-shim created
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-issuers created
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-orders created
clusterrole.rbac.authorization.k8s.io/cert-manager-edit created
clusterrole.rbac.authorization.k8s.io/cert-manager-view created
clusterrole.rbac.authorization.k8s.io/cert-manager-webhook:subjectaccessreviews created
rolebinding.rbac.authorization.k8s.io/cert-manager-cert-manager-tokenrequest created
rolebinding.rbac.authorization.k8s.io/cert-manager-startupapicheck:create-cert created
rolebinding.rbac.authorization.k8s.io/cert-manager-webhook:dynamic-serving created
rolebinding.rbac.authorization.k8s.io/proxmox-csi-plugin-controller created
rolebinding.rbac.authorization.k8s.io/cert-manager-cainjector:leaderelection created
rolebinding.rbac.authorization.k8s.io/cert-manager:leaderelection created
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-cainjector created
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-approve:cert-manager-io created
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-certificates created
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-certificatesigningrequests created
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-challenges created
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-clusterissuers created
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-ingress-shim created
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-issuers created
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-orders created
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-webhook:subjectaccessreviews created
clusterrolebinding.rbac.authorization.k8s.io/proxmox-csi-plugin-controller created
clusterrolebinding.rbac.authorization.k8s.io/proxmox-csi-plugin-node created
service/cert-manager created
service/cert-manager-cainjector created
service/cert-manager-webhook created
deployment.apps/cert-manager created
deployment.apps/cert-manager-cainjector created
deployment.apps/cert-manager-webhook created
deployment.apps/proxmox-csi-plugin-controller created
Warning: would violate PodSecurity "baseline:latest": non-default capabilities (container "proxmox-csi-plugin-node" must not include "SYS_ADMIN" in securityContext.capabilities.add), hostPath volumes (volumes "socket", "registration", "kubelet", "dev", "sys"), privileged (container "proxmox-csi-plugin-node" must not set securityContext.privileged=true)
daemonset.apps/proxmox-csi-plugin-node created
job.batch/cert-manager-startupapicheck created
sealedsecret.bitnami.com/cloudflare-api-token created
gateway.gateway.networking.k8s.io/external created
gateway.gateway.networking.k8s.io/internal created
Warning: resource gatewayclasses/cilium is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
gatewayclass.gateway.networking.k8s.io/cilium configured
csidriver.storage.k8s.io/csi.proxmox.sinextra.dev created
mutatingwebhookconfiguration.admissionregistration.k8s.io/cert-manager-webhook created
validatingwebhookconfiguration.admissionregistration.k8s.io/cert-manager-webhook created
resource mapping not found for name: "cert" namespace: "gateway" from "STDIN": no matches for kind "Certificate" in version "cert-manager.io/v1"
ensure CRDs are installed first
resource mapping not found for name: "cloudflare-cluster-issuer" namespace: "" from "STDIN": no matches for kind "ClusterIssuer" in version "cert-manager.io/v1"
ensure CRDs are installed first
```

### 2nd run

```sh
❯ kustomize build --enable-helm k8s/infra/_envs/$(kubectl config current-context | cut -d "@" -f 2 | cut -d "-" -f 1) | kubectl apply -f -
storageclass.storage.k8s.io/proxmox-csi unchanged
customresourcedefinition.apiextensions.k8s.io/certificaterequests.cert-manager.io unchanged
customresourcedefinition.apiextensions.k8s.io/certificates.cert-manager.io unchanged
customresourcedefinition.apiextensions.k8s.io/challenges.acme.cert-manager.io unchanged
customresourcedefinition.apiextensions.k8s.io/clusterissuers.cert-manager.io unchanged
customresourcedefinition.apiextensions.k8s.io/issuers.cert-manager.io unchanged
customresourcedefinition.apiextensions.k8s.io/orders.acme.cert-manager.io unchanged
serviceaccount/cert-manager unchanged
serviceaccount/cert-manager-cainjector unchanged
serviceaccount/cert-manager-startupapicheck unchanged
serviceaccount/cert-manager-webhook unchanged
serviceaccount/proxmox-csi-plugin-controller unchanged
serviceaccount/proxmox-csi-plugin-node unchanged
role.rbac.authorization.k8s.io/cert-manager-startupapicheck:create-cert unchanged
role.rbac.authorization.k8s.io/cert-manager-tokenrequest unchanged
role.rbac.authorization.k8s.io/cert-manager-webhook:dynamic-serving unchanged
role.rbac.authorization.k8s.io/proxmox-csi-plugin-controller unchanged
role.rbac.authorization.k8s.io/cert-manager-cainjector:leaderelection unchanged
role.rbac.authorization.k8s.io/cert-manager:leaderelection unchanged
clusterrole.rbac.authorization.k8s.io/proxmox-csi-plugin-controller unchanged
clusterrole.rbac.authorization.k8s.io/proxmox-csi-plugin-node unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-cainjector unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-cluster-view unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-approve:cert-manager-io unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-certificates unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-certificatesigningrequests unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-challenges unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-clusterissuers unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-ingress-shim unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-issuers unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-orders unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-edit unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-view unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-webhook:subjectaccessreviews unchanged
rolebinding.rbac.authorization.k8s.io/cert-manager-cert-manager-tokenrequest unchanged
rolebinding.rbac.authorization.k8s.io/cert-manager-startupapicheck:create-cert unchanged
rolebinding.rbac.authorization.k8s.io/cert-manager-webhook:dynamic-serving unchanged
rolebinding.rbac.authorization.k8s.io/proxmox-csi-plugin-controller unchanged
rolebinding.rbac.authorization.k8s.io/cert-manager-cainjector:leaderelection unchanged
rolebinding.rbac.authorization.k8s.io/cert-manager:leaderelection unchanged
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-cainjector unchanged
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-approve:cert-manager-io unchanged
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-certificates unchanged
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-certificatesigningrequests unchanged
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-challenges unchanged
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-clusterissuers unchanged
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-ingress-shim unchanged
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-issuers unchanged
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-orders unchanged
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-webhook:subjectaccessreviews unchanged
clusterrolebinding.rbac.authorization.k8s.io/proxmox-csi-plugin-controller unchanged
clusterrolebinding.rbac.authorization.k8s.io/proxmox-csi-plugin-node unchanged
service/cert-manager unchanged
service/cert-manager-cainjector unchanged
service/cert-manager-webhook unchanged
deployment.apps/cert-manager unchanged
deployment.apps/cert-manager-cainjector unchanged
deployment.apps/cert-manager-webhook unchanged
deployment.apps/proxmox-csi-plugin-controller configured
daemonset.apps/proxmox-csi-plugin-node unchanged
job.batch/cert-manager-startupapicheck unchanged
sealedsecret.bitnami.com/cloudflare-api-token unchanged
Warning: spec.privateKey.rotationPolicy: In cert-manager >= v1.18.0, the default value changed from `Never` to `Always`.
certificate.cert-manager.io/cert created
clusterissuer.cert-manager.io/cloudflare-cluster-issuer created
gateway.gateway.networking.k8s.io/external configured
gatewayclass.gateway.networking.k8s.io/cilium unchanged
csidriver.storage.k8s.io/csi.proxmox.sinextra.dev unchanged
mutatingwebhookconfiguration.admissionregistration.k8s.io/cert-manager-webhook configured
validatingwebhookconfiguration.admissionregistration.k8s.io/cert-manager-webhook configured
Error from server: error when retrieving current configuration of:
Resource: "/v1, Resource=namespaces", GroupVersionKind: "/v1, Kind=Namespace"
Name: "cert-manager", Namespace: ""
from server for: "STDIN": etcdserver: request timed out
Error from server: error when retrieving current configuration of:
Resource: "/v1, Resource=namespaces", GroupVersionKind: "/v1, Kind=Namespace"
Name: "gateway", Namespace: ""
from server for: "STDIN": etcdserver: leader changed
Error from server: error when retrieving current configuration of:
Resource: "gateway.networking.k8s.io/v1, Resource=gateways", GroupVersionKind: "gateway.networking.k8s.io/v1, Kind=Gateway"
Name: "internal", Namespace: "gateway"
from server for: "STDIN": etcdserver: leader changed
```

### 3rd run

```sh
❯ kustomize build --enable-helm k8s/infra/\_envs/$(kubectl config current-context | cut -d "@" -f 2 | cut -d "-" -f 1) | kubectl apply -f -
namespace/cert-manager unchanged
namespace/gateway unchanged
storageclass.storage.k8s.io/proxmox-csi unchanged
customresourcedefinition.apiextensions.k8s.io/certificaterequests.cert-manager.io unchanged
customresourcedefinition.apiextensions.k8s.io/certificates.cert-manager.io unchanged
customresourcedefinition.apiextensions.k8s.io/challenges.acme.cert-manager.io unchanged
customresourcedefinition.apiextensions.k8s.io/clusterissuers.cert-manager.io unchanged
customresourcedefinition.apiextensions.k8s.io/issuers.cert-manager.io unchanged
customresourcedefinition.apiextensions.k8s.io/orders.acme.cert-manager.io unchanged
serviceaccount/cert-manager unchanged
serviceaccount/cert-manager-cainjector unchanged
serviceaccount/cert-manager-startupapicheck unchanged
serviceaccount/cert-manager-webhook unchanged
serviceaccount/proxmox-csi-plugin-controller unchanged
serviceaccount/proxmox-csi-plugin-node unchanged
role.rbac.authorization.k8s.io/cert-manager-startupapicheck:create-cert unchanged
role.rbac.authorization.k8s.io/cert-manager-tokenrequest unchanged
role.rbac.authorization.k8s.io/cert-manager-webhook:dynamic-serving unchanged
role.rbac.authorization.k8s.io/proxmox-csi-plugin-controller unchanged
role.rbac.authorization.k8s.io/cert-manager-cainjector:leaderelection unchanged
role.rbac.authorization.k8s.io/cert-manager:leaderelection unchanged
clusterrole.rbac.authorization.k8s.io/proxmox-csi-plugin-controller unchanged
clusterrole.rbac.authorization.k8s.io/proxmox-csi-plugin-node unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-cainjector unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-cluster-view unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-approve:cert-manager-io unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-certificates unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-certificatesigningrequests unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-challenges unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-clusterissuers unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-ingress-shim unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-issuers unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-controller-orders unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-edit unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-view unchanged
clusterrole.rbac.authorization.k8s.io/cert-manager-webhook:subjectaccessreviews unchanged
rolebinding.rbac.authorization.k8s.io/cert-manager-cert-manager-tokenrequest unchanged
rolebinding.rbac.authorization.k8s.io/cert-manager-startupapicheck:create-cert unchanged
rolebinding.rbac.authorization.k8s.io/cert-manager-webhook:dynamic-serving unchanged
rolebinding.rbac.authorization.k8s.io/proxmox-csi-plugin-controller unchanged
rolebinding.rbac.authorization.k8s.io/cert-manager-cainjector:leaderelection unchanged
rolebinding.rbac.authorization.k8s.io/cert-manager:leaderelection unchanged
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-cainjector unchanged
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-approve:cert-manager-io unchanged
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-certificates unchanged
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-certificatesigningrequests unchanged
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-challenges unchanged
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-clusterissuers unchanged
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-ingress-shim unchanged
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-issuers unchanged
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-controller-orders unchanged
clusterrolebinding.rbac.authorization.k8s.io/cert-manager-webhook:subjectaccessreviews unchanged
clusterrolebinding.rbac.authorization.k8s.io/proxmox-csi-plugin-controller unchanged
clusterrolebinding.rbac.authorization.k8s.io/proxmox-csi-plugin-node unchanged
service/cert-manager unchanged
service/cert-manager-cainjector unchanged
service/cert-manager-webhook unchanged
deployment.apps/cert-manager unchanged
deployment.apps/cert-manager-cainjector unchanged
deployment.apps/cert-manager-webhook unchanged
deployment.apps/proxmox-csi-plugin-controller configured
daemonset.apps/proxmox-csi-plugin-node unchanged
job.batch/cert-manager-startupapicheck unchanged
sealedsecret.bitnami.com/cloudflare-api-token unchanged
certificate.cert-manager.io/cert unchanged
clusterissuer.cert-manager.io/cloudflare-cluster-issuer unchanged
gateway.gateway.networking.k8s.io/external configured
gateway.gateway.networking.k8s.io/internal configured
gatewayclass.gateway.networking.k8s.io/cilium unchanged
csidriver.storage.k8s.io/csi.proxmox.sinextra.dev unchanged
mutatingwebhookconfiguration.admissionregistration.k8s.io/cert-manager-webhook configured
validatingwebhookconfiguration.admissionregistration.k8s.io/cert-manager-webhook configured

```

## whoami

```sh
❯ kustomize build --enable-helm k8s/apps/diag/whoami/envs/prod/ | kaf -
namespace/whoami created
service/whoami created
deployment.apps/whoami created
httproute.gateway.networking.k8s.io/whoami-ingress created
```
