# Longhorn login

A login in front of the Longhorn dashboard: an OAuth2 Proxy against the Keycloak realm `admin`, and a network policy that lets nothing reach the dashboard around it.

## At a glance

| | |
| --- | --- |
| Namespace | `longhorn-system` |
| Runs in | `dev`, `prod`, `qa` (no Flux set, registered in `k8s/bootstrap/cluster/flux/envs/<env>/kustomization.yaml`) |
| Installed via | the shared component [`oauth2-proxy`](../../../components/apps/oauth2-proxy/README.md) (HelmRelease, OCIRepository, ExternalSecret) plus a `CiliumNetworkPolicy` |
| Flux Kustomization | `longhorn-auth`, depends on `longhorn-core` |

## Purpose

The Longhorn dashboard and its API have no authentication, and the `HTTPRoute` published them to the whole LAN ([#1725](https://github.com/isejalabs/homelab/issues/1725), [#2228](https://github.com/isejalabs/homelab/issues/2228)). Longhorn has no login to turn on, so [ADR 0016](../../../../docs/decisions/0016-identity-and-web-sso.md) (point 8) puts a proxy in front: only `sebi-adm`, member of the UCS group `sec.app.longhorn.admin`, gets in. The `CiliumNetworkPolicy` `longhorn-ui-only-from-oauth2-proxy` admits only the proxy to the UI pods, so the Gateway and other namespaces cannot bypass it. How it fits together, the monitoring exception, break-glass and the decision on `sebi` and `mary` ([#2229](https://github.com/isejalabs/homelab/issues/2229)): [`longhorn-sso.md`](../../../../docs/identity/longhorn-sso.md).

## Where it is used

- **Used by**: the Longhorn dashboard route in [`longhorn-core`](../longhorn-core/README.md); in the environments that run this unit, the route's `backendRef` points at the Service `oauth2-proxy` instead of `longhorn-frontend` (`envs/<env>/http-route-oauth2-proxy.yaml` of `longhorn-core`).
- **Depends on**: `longhorn-core` (the UI), the Keycloak of the environment and its client, and the 1Password items `keycloak-oidc-longhorn-admin#<env>` and `oauth2-proxy-longhorn#<env>` (External Secrets).

## Access

Not exposed on its own; the in-cluster Service is `oauth2-proxy` in `longhorn-system`. The dashboard hostnames are in [`longhorn-core`](../longhorn-core/README.md#access).

## Updates

The proxy's chart is pinned once for all consumers in the component, see its [Updates](../../../components/apps/oauth2-proxy/README.md#updates). The issuer URL of each environment (`envs/<env>/issuer.yaml`) must equal the hostname of that environment's Keycloak.

## Operations

| Task | Doc |
| --- | --- |
| How the login works, the monitoring path, sign in without Keycloak | [`longhorn-sso.md`](../../../../docs/identity/longhorn-sso.md) |
| Reuse the proxy for another application | [`oauth2-proxy.md`](../../../../docs/identity/oauth2-proxy.md) |
| Name or change a UCS access group | [`ucs-groups.md`](../../../../docs/identity/ucs-groups.md) |

## Cheat sheet

```sh
flux get ks longhorn-auth --context admin@<env>-homelab
kubectl get helmrelease,externalsecret -n longhorn-system --context admin@<env>-homelab
kubectl logs -n longhorn-system deploy/oauth2-proxy --context admin@<env>-homelab

# break-glass: the dashboard without Keycloak, then open http://localhost:8080
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80 --context admin@<env>-homelab
```

## Upstream

- OAuth2 Proxy: <https://oauth2-proxy.github.io/oauth2-proxy/>, chart <https://github.com/oauth2-proxy/manifests>
