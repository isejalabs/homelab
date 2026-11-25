## Purpose

The Keycloak login of the Flux Operator Web UI and the Kubernetes RBAC behind it, as one block that each environment with a Keycloak includes. Background, claim handling and the decisions: [`docs/identity/flux-operator-sso.md`](../../../../docs/identity/flux-operator-sso.md).

## What it creates

| Object | Name | Purpose |
| --- | --- | --- |
| `HelmRelease` (patch) | `flux-operator` | Adds the `web.config` of the OIDC login (client `flux-operator`, claim rules, `FineGrained` actions) and the client secret from the Secret below |
| `ExternalSecret` | `flux-operator-oidc` | The Secret with the client secret, from the 1Password item `keycloak-oidc-flux-operator-admin#<env>` that the `keycloak-realm` unit writes |
| `ClusterRole` | `flux-operator-web-admin` | What the group needs to see Flux and its workloads and to run the Flux actions, without `Secret` and `ConfigMap` access |
| `ClusterRoleBinding` | `flux-operator-web-admin` | Binds the group `sec.app.flux-operator.admin` to that role |

## Wiring it up

An environment includes the component next to its `components/envs/<env>` and patches three values in `envs/<env>/kustomization.yaml`: the 1Password item suffix (`#base` becomes `#<env>`), and the `issuerURL` and `baseURL` of the `HelmRelease` (the base values use `example.com`, which no transformer rewrites in a `HelmRelease`). The Keycloak client with the redirect URI `https://<flux host>/oauth2/callback` comes from `oidc_clients` in the environment's `keycloak-realm` unit and must exist (with its 1Password item) before the overlay is merged, otherwise the `HelmRelease` waits for the Secret.

```yaml
components:
  - ../../../../../components/envs/<env>
  - ../../../../../components/apps/flux-operator-sso
```

## Used by

[`flux-operator`](../../../infra/flux-system/flux-operator/README.md) in `dev`, `qa` and `prod`.
