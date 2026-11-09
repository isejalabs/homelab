---
status: draft
---

# Flux Operator Web UI SSO

Browser sign-in to the Flux Operator Web UI through the identity provider of [ADR 0016](../decisions/0016-identity-and-web-sso.md). Tracking: [#1726](https://github.com/isejalabs/homelab/issues/1726); the first scenario (`sebi-adm`, realm `admin`) is [#2233](https://github.com/isejalabs/homelab/issues/2233), the operator and read-only roles are [#2234](https://github.com/isejalabs/homelab/issues/2234). Rollout rules: [#2198](https://github.com/isejalabs/homelab/issues/2198).

**Status (2026-11-09):** prepared for `dev`, as code only. The client is declared in the `dev` `keycloak-realm` unit but not applied, and nothing is applied to a cluster. `oidc_clients` exists since [#2227](https://github.com/isejalabs/homelab/issues/2227).

## How it works

The Web UI of the operator (port 9080, published by the `HTTPRoute` of [`flux-operator`](../../k8s/infra/flux-system/flux-operator/README.md#access)) has native OIDC. After the login it **impersonates** the user against the Kubernetes API with the username and groups it extracted from the ID token, so Kubernetes RBAC is the authorization and the UI adds no rules of its own. No gateway filter or proxy is involved.

| Part | Where it lives |
| --- | --- |
| Keycloak client `flux-operator` in the realm `admin` | Code: entry `flux-operator-admin` in `oidc_clients` of the unit [`dev/keycloak-realm`](../../terragrunt/non-prod/eu-central-1/dev/keycloak-realm/terragrunt.hcl) ([OIDC clients](keycloak-realms.md#oidc-clients)); redirect URI `https://<flux host>/oauth2/callback` |
| Client secret | 1Password item `keycloak-oidc-flux-operator-admin#<env>` (field `password`), written by the `keycloak-realm` unit and delivered by an `ExternalSecret`, rendered by the chart into the web config; never in Git |
| Web config (issuer, claim rules) | `HelmRelease` values `web.config` in [`envs/<env>/helmrelease.yaml`](../../k8s/infra/flux-system/flux-operator/envs/dev/helmrelease.yaml) |
| Authorization | `ClusterRoleBinding` of the group `sec.app.flux-operator.admin` to the chart's `flux-web-admin` |
| UCS group | `sec.app.flux-operator.admin`, member `sebi-adm` ([`ucs-groups.md`](ucs-groups.md)); creation needs the owner's go |

## Claim handling

The operator's service account may impersonate **any** user and group, so a claim that is forwarded unfiltered would be an escalation (the class of GO-2026-4351, an empty claim granted access before 0.40.0). The config therefore does not use the defaults (`email`, `groups`):

- **groups:** only the entries that start with `sec.app.flux-operator.` are impersonated, a leading `/` (Keycloak's full group path) is removed first. Other groups of the token, for example a `system:masters`, never reach the API server.
- **username:** `oidc:` plus `preferred_username`, so it cannot equal a service account or a `system:` user and the audit log shows where the request came from. Keep the prefix in step with the Kubernetes API OIDC work ([#1766](https://github.com/isejalabs/homelab/issues/1766)).
- **validations:** the login is refused when no `sec.app.flux-operator.*` group is left or the username is empty. A missing `groups` claim yields an empty list (`has()` guard), so it never grants anything and never errors into a default.

## Versions

Flux Operator **0.62.1** (chart and app, pinned in [`ocirepository.yaml`](../../k8s/infra/flux-system/flux-operator/base/ocirepository.yaml)), checked live on 2026-11-08 in `dbg`, `dev`, `prod`, `qa` and `rebuild`; `poc` and `src` were unreachable and share the pin. The minimum is 0.40.0 (GO-2026-4351), so no upgrade is needed.

## Rollout state

| env | Config | Applied | Verified |
| --- | --- | --- | --- |
| `dev` | prepared | no | no |
| `qa` | no | no | no |
| `prod` | no | no | no |

Environments without a Keycloak (`dbg`, `head`, `poc`, `rebuild`, `src`) keep the UI as it is: no login, the identity of the operator's service account. That is a decision of the Web UI default, not of this change.

## Break-glass

The `kubectl` and `flux` CLI with the Talos-issued admin kubeconfig do not use the Web UI or Keycloak, and Flux reconciliation does not depend on the UI login: if Keycloak is down, only the browser login fails. To go back to the open UI, remove `valuesFrom` and `web.config` from the overlay (or `helm upgrade` by hand).

## Open points

- Apply the `dev` `keycloak-realm` unit (the owner's go; plan must only add the client, its default scopes and the 1Password item), then roll out the overlay with the `track-branch` skill.
- MFA behaviour of the realm `admin` is recorded after the first real login.
- Roles for `sebi` and `mary` and the question of a second realm: [#2234](https://github.com/isejalabs/homelab/issues/2234).
