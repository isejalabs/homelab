## Purpose

The Keycloak login of Immich as one block that each environment with a Keycloak includes. Background, what Immich can and cannot do, and the decisions: [`docs/identity/immich-sso.md`](../../../../docs/identity/immich-sso.md).

## What it creates

| Object | Name | Purpose |
| --- | --- | --- |
| `HelmRelease` (patch) | `immich` | Adds `immich.configuration.oauth` (issuer, client `immich`, scope, `autoRegister: false`, mobile redirect override), switches the settings file to a Secret (`configurationKind: Secret`) and reads the client secret into it through `valuesFrom` |
| `ExternalSecret` | `immich-oidc` | The Secret with the client secret, from the 1Password item `keycloak-oidc-immich-iseja#<env>` that the `keycloak-realm` unit writes |

## Wiring it up

An environment includes the component next to its `components/envs/<env>` and patches, in `envs/<env>/kustomization.yaml`, the 1Password item suffix (`#base` becomes `#<env>`) and three values of the `HelmRelease`: `issuerUrl`, `accountManagementUrl` and `mobileRedirectUri` (the base values use `example.com`, which no transformer rewrites inside a `HelmRelease`). The Keycloak client with the redirect URIs `https://<immich host>/auth/login`, `/user-settings` and `/api/oauth/mobile-redirect` comes from `oidc_clients` in the `keycloak-realm` unit of the environment and must exist (with its 1Password item) before the overlay is merged, otherwise the `HelmRelease` waits for the Secret.

```yaml
components:
  - ../../../../../components/envs/<env>
  - ../../../../../components/apps/immich-sso
```

## Used by

[`immich`](../../../apps/media/immich/README.md) in `dev` and `qa`; the `prod` overlay includes it for the promotion.
