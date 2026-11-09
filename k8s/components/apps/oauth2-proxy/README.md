## Purpose

A login in front of a web UI that has none of its own. The component installs one [OAuth2 Proxy](https://oauth2-proxy.github.io/oauth2-proxy/) in the application's namespace, as a plain reverse proxy that authenticates against the Keycloak realm `admin` and lets through only the members of one UCS group. It is the pattern of [ADR 0016](../../../../docs/decisions/0016-identity-and-web-sso.md) (point 8) for applications without native OIDC: Longhorn ([`longhorn-auth`](../../../infra/longhorn-system/longhorn-auth/README.md)), and next Zigbee2MQTT and AdGuard. The how-to, the trade-offs and what the pattern does not cover are in [`docs/identity/oauth2-proxy.md`](../../../../docs/identity/oauth2-proxy.md); this page is the reference of the component itself.

## What it creates

| Object | Name | Purpose |
| --- | --- | --- |
| `OCIRepository` | `oauth2-proxy` | The upstream Helm chart `ghcr.io/oauth2-proxy/charts/oauth2-proxy`, pinned by tag and digest (Renovate bumps both) |
| `HelmRelease` | `oauth2-proxy` | The proxy: one replica, session in an encrypted cookie, `keycloak-oidc` provider, PKCE `S256`, authorization by the `groups` claim |
| `ExternalSecret` | `oauth2-proxy` | The Secret `oauth2-proxy` with `client-id`, `client-secret` and `cookie-secret`, from the 1Password items `keycloak-oidc-<APP>-admin#<env>` and `oauth2-proxy-<APP>#<env>` |

The names are fixed (one proxy per namespace). The Service is `oauth2-proxy` on port 80, the pods carry `app.kubernetes.io/name: oauth2-proxy` and `app.kubernetes.io/instance: oauth2-proxy`.

## Wiring it up

Four things belong to the consumer, none of them in this component:

1. **The unit.** `base/kustomization.yaml` sets `namespace:` and lists the component; the unit gets a Flux `Kustomization` like any other.

   ```yaml
   components:
     - ../../../../components/apps/oauth2-proxy
   ```

2. **Three Flux variables** in the `postBuild.substitute` of `flux/ks.yaml`:

   | Variable | Meaning |
   | --- | --- |
   | `APP` | the application, only used in the 1Password item name |
   | `OAUTH2_PROXY_ALLOWED_GROUP` | the UCS group that may log in, for example `sec.app.longhorn.admin` |
   | `OAUTH2_PROXY_UPSTREAM` | the in-cluster URL of the application, for example `http://longhorn-frontend.longhorn-system.svc:80` |

3. **Two patches per environment** in `envs/<env>/kustomization.yaml`: the realm's issuer in `spec.values.extraArgs.oidc-issuer-url` of the `HelmRelease` (the base value `https://auth.example.com/realms/admin` is a placeholder; the host is that of the environment's Keycloak) and the `#base` suffix of the `ExternalSecret` key. Use `target: {kind: ...}` without a name, as the longhorn-auth overlays do. Further arguments (a path that skips the login, a different cookie lifetime) are `extraArgs` patches in the same way.

4. **The things around it**: a `CiliumNetworkPolicy` that admits only the proxy to the application, the route's `backendRef` pointing at the Service `oauth2-proxy`, and the Keycloak client with the redirect URI `https://<hostname>/oauth2/callback` (Terragrunt, `oidc_clients` of the `keycloak-realm` unit).

## Secrets

`config.existingSecret` makes the chart read the three keys from the Secret the `ExternalSecret` writes, so nothing secret is in Git. Client ID and secret come from the 1Password item `keycloak-oidc-<APP>-admin#<env>` that Terragrunt writes for the client (username and password of a login item, see [`keycloak-realms.md`](../../../../docs/identity/keycloak-realms.md#oidc-clients)); the `cookie-secret` is a hand-made item `oauth2-proxy-<APP>#<env>` with one field of that name, 32 random bytes (for example `openssl rand -base64 32 | tr -- '+/' '-_'`). Rotating the cookie secret logs everybody out once.

## Updates

The chart version is pinned in [`ocirepository.yaml`](ocirepository.yaml) (`ref.tag` and `ref.digest`). It is one place for all consumers: a bump rolls out to every proxy of every environment at once, and the proxy image follows the chart's `appVersion`.
