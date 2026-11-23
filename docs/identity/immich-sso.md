---
status: current
---

# Immich sign-in with Keycloak

Immich signs its users in with OpenID Connect against the realm `iseja` of the identity provider ([ADR 0016](../decisions/0016-identity-and-web-sso.md), point 8). Tracking: [#1768](https://github.com/isejalabs/homelab/issues/1768) (parent), [#2440](https://github.com/isejalabs/homelab/issues/2440) (Keycloak client), [#2441](https://github.com/isejalabs/homelab/issues/2441) (Immich login), [#2442](https://github.com/isejalabs/homelab/issues/2442) (this page), [#2443](https://github.com/isejalabs/homelab/issues/2443) (`prod`). Rollout rules: [#2198](https://github.com/isejalabs/homelab/issues/2198).

**Status (2026-11-22):** the client is applied and the login is verified in `dev` and `qa` (browser and mobile app, plus the local administrator); `prod` follows with the promotion. The decisions below were taken by the owner on 2026-11-22. `dev` and `qa` run Immich, `prod` does not yet ([#2149](https://github.com/isejalabs/homelab/issues/2149)).

## What Immich can and cannot do

Read in the source and documentation of the deployed version, Immich **v3.4.2** ([OAuth page](https://docs.immich.app/administration/oauth), `server/src/services/auth.service.ts`, `server/src/utils/config.ts`).

| Question | Answer |
| --- | --- |
| How many issuers? | **One.** The settings have a single `issuerUrl` and client. Immich cannot trust both realms `iseja` and `admin`. |
| Group check at login? | **No.** The server ignores a `groups` claim. Who may sign in is decided by the realm (`sec.idm.users`) and by `autoRegister`. |
| Role from the token? | Optional claim (`roleClaim`, default `immich_role`). A **present** claim sets `isAdmin` at **every** login: any value containing `admin` makes the account an administrator, any other value (also `sec.app.immich.admin`, which is not `admin`) demotes it to user. An absent claim changes nothing. The claim would need a Keycloak mapper that the module does not offer. |
| Link to an existing account | At the first login an account without a link is matched by the **e-mail address** of the token and gets the issuer's `sub`; a different account already linked to that address makes the login fail. Without an e-mail claim the login fails. |
| Auto registration | `autoRegister` (default on) creates an account at the first login, with the storage label from `storageLabelClaim` (default `preferred_username`; a later change of the claim value is not synced for the default claim). |
| PKCE | Always sent, S256, when the issuer advertises it. The Keycloak client requires it. |
| Mobile app | Redirect `app.immich:///oauth-callback`. The Keycloak module registers https URIs only, so the setting `mobileOverrideEnabled` replaces it with `https://<host>/api/oauth/mobile-redirect`, a route of Immich that forwards to the custom scheme. |
| Token refresh against the issuer | **None found.** The server does not use the refresh token: after the login Immich issues its own session. The note of the planning phase that the mobile app refreshes tokens in the background and fails during an IdP outage was **not confirmed in the server source**; the mobile app's code was not read. Backchannel logout (`/api/oauth/backchannel-logout`) exists and is not used yet (the module has no field for it). |
| Settings file | `IMMICH_CONFIG_FILE` is YAML or JSON, **no substitution of environment variables or files**, so the client secret has to be in the file itself. The file locks the whole settings page. |
| Recovery commands | `immich-admin` has `enable-password-login`, `disable-oauth-login`, `grant-admin`, `reset-admin-password`. The first two write the database configuration, which the settings file overrides: **with a file they have no effect**. |

## Decisions (owner, 2026-11-22)

1. **Realm `iseja` only.** Immich trusts one issuer, and the people who own photos are everyday accounts (`bob`, `alice`, ...). There is no `admin` realm client and no `*-adm` login for Immich.
2. **Administration stays local.** The administrator of Immich is a local account with a generated password (1Password), and password login stays on. It is also the break-glass. SSO never changes the administrator flag: no role claim, no group `sec.app.immich.admin`. The `bob-adm` identity is not used in Immich.
3. **`autoRegister` is off.** An administrator creates every Immich account (name, e-mail address as in the directory, **storage label** equal to the person's short name, ADR 0018 rule 4). The first SSO login links the account by e-mail. The allowlist therefore lives in Immich. No UCS group `sec.app.immich.*` is created: Immich cannot read it, and an unused group would suggest a control that does not exist. With `autoRegister` on, every account of the realm would get an Immich account at its first login, because nothing in front of Immich limits who may sign in; a Keycloak-side gate (a per-client flow that denies accounts without a role from a UCS group) is possible with stock Keycloak but is not in the `keycloak-realm` module yet. The re-evaluation and the options are in a [comment on #1768](https://github.com/isejalabs/homelab/issues/1768#issuecomment-7082762625).
4. **Machine and API credentials stay separate.** API keys (CLI, scripts) and the mobile app's session are Immich's own and independent of Keycloak.

Consequences: the realm requires a second factor for every password login ([`keycloak-mfa.md`](keycloak-mfa.md)), so Immich's web login has it; the **local** accounts (administrator, the shared `household` owner of the external libraries) have only a password. A directory e-mail address that is wrong or changed makes the first link fail (it does not grant access to another account), a changed address after linking has no effect because the link is the `sub`.

## How it works

| Part | Where it lives |
| --- | --- |
| Keycloak client `immich` in the realm `iseja` | Entry `immich-iseja` in `oidc_clients` of the `keycloak-realm` unit of [`dev`](../../terragrunt/non-prod/eu-central-1/dev/keycloak-realm/terragrunt.hcl) and [`qa`](../../terragrunt/non-prod/eu-central-1/qa/keycloak-realm/terragrunt.hcl) ([OIDC clients](keycloak-realms.md#oidc-clients)); `prod` gets its entry with the promotion ([#2443](https://github.com/isejalabs/homelab/issues/2443)). Confidential, PKCE, redirect URIs `<url>/auth/login`, `<url>/user-settings`, `<url>/api/oauth/mobile-redirect` |
| Client secret | 1Password item `keycloak-oidc-immich-iseja#<env>` (field `password`), delivered by the `ExternalSecret` `immich-oidc`; never in Git |
| Settings | `immich.configuration.oauth` in the `HelmRelease`, from the shared component [`immich-sso`](../../k8s/components/apps/immich-sso/README.md): issuer, client, scope `openid email profile`, `autoRegister: false`, mobile override. The secret enters through `valuesFrom` (`targetPath` `immich.configuration.oauth.clientSecret`), and the chart renders the file into a **Secret** (`configurationKind: Secret`) instead of a ConfigMap |
| Environments | `dev`, `qa` and the (not yet registered) `prod` overlay include the component; `rebuild` has no Keycloak and keeps the interim password login |

## Create an account for a person

1. Sign in with the local administrator ([below](#administrator-and-break-glass)). *Administration > Users > Create user*: the **e-mail address of the directory account** (it is the link), a long random password that is not kept anywhere (the form requires one, the login does not use it; with password login on it stays a second way in, so nobody should know it), the name, the **storage label** (the short name, for example `bob`), and *Require password change on next login* unticked.
2. The person opens the Immich URL and chooses *Sign in with Keycloak*: a first-time login links the account. In the mobile app, set the server URL and use the same button.
3. Remove access: delete the Immich user. Removing the person from `sec.idm.users` stops new Keycloak logins, but a session that Immich already issued is not ended by Keycloak (backchannel logout is not set up).

## Administrator and break-glass

- The local administrator account is created by the registration at the first start (before anyone else knows the address) and its password is in the password manager. Password login is on in every environment.
- **Keycloak or UCS down:** sign in with the local administrator; everyday accounts wait for the identity provider (no refresh against the issuer is involved, so open sessions continue).
- **Locked out of everything:** the settings are a file, so `immich-admin enable-password-login` does nothing. Set `immich.configuration.passwordLogin.enabled: true` in the overlay (Git, Flux) or, when Flux is unavailable, patch the Secret `immich-immich-config` and restart the server. The admin CLI works for what lives in the database: `kubectl exec -n immich deploy/immich-server -- immich-admin reset-admin-password` and `grant-admin`.
- **Interim authentication:** every account that existed before SSO keeps working with its password and is linked by e-mail at its first SSO login. Passwords of linked accounts can stay set; they matter only while password login is enabled.

## Rollout state

| env | Client | Settings | Verified |
| --- | --- | --- | --- |
| `dev` | yes (2026-11-22) | on `main` with the merge | yes, browser login (2026-11-22): a pre-created account links and signs in, an account without an Immich user is refused |
| `qa` | yes (2026-11-22, applied from `main`) | on `main` | yes (2026-11-22): browser login of a pre-created account, mobile app login, local administrator with password (break-glass) |
| `prod` | no (with the promotion) | overlay prepared, unit not registered | no |

## Open points

- `prod`: register the client and apply it from `main` with the promotion, once Immich runs there ([#2443](https://github.com/isejalabs/homelab/issues/2443), blocked by [#2149](https://github.com/isejalabs/homelab/issues/2149)).
- Keycloak-side group gate and then `autoRegister` on: see the [comment on #1768](https://github.com/isejalabs/homelab/issues/1768#issuecomment-7082762625); not decided.
- Backchannel logout and an `immich_role` mapper are possible later module extensions; not needed under the decisions above.
