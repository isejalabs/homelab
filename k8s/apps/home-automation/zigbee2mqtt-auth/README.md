# Zigbee2MQTT login

A login in front of the Zigbee2MQTT web frontend: an OAuth2 Proxy against the Keycloak realm `admin`, and a network policy that lets nothing reach the frontend around it.

## At a glance

| | |
| --- | --- |
| Namespace | `zigbee2mqtt` |
| Runs in | `prod` (no Flux set, registered in [`flux/envs/prod`](../../../bootstrap/cluster/flux/envs/prod/kustomization.yaml)); Zigbee2MQTT runs in no other environment |
| Installed via | the shared component [`oauth2-proxy`](../../../components/apps/oauth2-proxy/README.md) (HelmRelease, OCIRepository, ExternalSecret) plus a `CiliumNetworkPolicy` |
| Flux Kustomization | `zigbee2mqtt-auth`, depends on `zigbee2mqtt` |

## Purpose

The Zigbee2MQTT frontend has no login that a single sign-on can use: its only protection is one shared token on the websocket, which a proxy cannot supply, and every websocket message becomes an MQTT publish (restart, `permit_join`, device `set`). So [ADR 0016](../../../../docs/decisions/0016-identity-and-web-sso.md) (point 8) puts a proxy in front: only `bob-adm`, member of the UCS group `sec.app.zigbee2mqtt.admin`, gets in. The `CiliumNetworkPolicy` `zigbee2mqtt-only-from-oauth2-proxy` admits only the proxy to the Zigbee2MQTT pod, so the Gateway and other pods cannot bypass it. Why this and not Zigbee2MQTT's own token or the Gateway `ExternalAuth`, how the websocket behaves behind the proxy, the break-glass and the decision on the everyday accounts: [`zigbee2mqtt-sso.md`](../../../../docs/identity/zigbee2mqtt-sso.md) ([#2230](https://github.com/isejalabs/homelab/issues/2230), [#2231](https://github.com/isejalabs/homelab/issues/2231), [#2232](https://github.com/isejalabs/homelab/issues/2232)).

## Where it is used

- **Used by**: the frontend route of [`zigbee2mqtt`](../zigbee2mqtt/README.md): in `prod`, the route's `backendRef` points at the Service `oauth2-proxy` instead of `zigbee2mqtt` (`rules` in `envs/prod/helmrelease.yaml` of `zigbee2mqtt`).
- **Depends on**: `zigbee2mqtt` (the pod the policy selects), the Keycloak of `prod` and its client `zigbee2mqtt`, and the 1Password items `keycloak-oidc-zigbee2mqtt-admin#prod` and `oauth2-proxy-zigbee2mqtt#prod` (External Secrets).

## Access

Not exposed on its own; the in-cluster Service is `oauth2-proxy` in `zigbee2mqtt`. The frontend hostname is in [`zigbee2mqtt`](../zigbee2mqtt/README.md#access).

## Updates

The proxy's chart is pinned once for all consumers in the component, see its [Updates](../../../components/apps/oauth2-proxy/README.md#updates). The issuer URL (`envs/prod/issuer.yaml`) must equal the hostname of the environment's Keycloak. The unit sets one argument of its own, `cookie-samesite: lax`, for the reasons in [`zigbee2mqtt-sso.md`](../../../../docs/identity/zigbee2mqtt-sso.md#how-the-proxy-route-behaves).

## Operations

| Task | Doc |
| --- | --- |
| How the login works, the websocket behaviour, sign in without Keycloak | [`zigbee2mqtt-sso.md`](../../../../docs/identity/zigbee2mqtt-sso.md) |
| Reuse the proxy for another application | [`oauth2-proxy.md`](../../../../docs/identity/oauth2-proxy.md) |
| Name or change a UCS access group | [`ucs-groups.md`](../../../../docs/identity/ucs-groups.md) |

## Cheat sheet

```sh
flux get ks zigbee2mqtt-auth --context admin@prod-homelab
kubectl get helmrelease,externalsecret,ciliumnetworkpolicy -n zigbee2mqtt --context admin@prod-homelab
kubectl logs -n zigbee2mqtt deploy/oauth2-proxy --context admin@prod-homelab

# break-glass: the frontend without Keycloak, then open http://localhost:8080
kubectl port-forward -n zigbee2mqtt svc/zigbee2mqtt 8080:8080 --context admin@prod-homelab
```

## Upstream

- OAuth2 Proxy: <https://oauth2-proxy.github.io/oauth2-proxy/>, chart <https://github.com/oauth2-proxy/manifests>
