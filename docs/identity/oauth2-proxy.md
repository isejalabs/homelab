---
status: current
---

# OAuth2 Proxy in front of a web UI

How an application with no login of its own gets one from the identity provider ([ADR 0016](../decisions/0016-identity-and-web-sso.md), point 8; [service matrix](../plans/2026-10-identity-claude.md#service-matrix)). The first user is Longhorn ([`longhorn-sso.md`](longhorn-sso.md)); Healthchecks ([#2275](https://github.com/isejalabs/homelab/issues/2275), with `REMOTE_USER_HEADER` and `/ping/` as the one path without login, see [`healthchecks`](../../k8s/apps/monitoring/healthchecks/README.md)), Zigbee2MQTT ([#1767](https://github.com/isejalabs/homelab/issues/1767)) and AdGuard ([#1830](https://github.com/isejalabs/homelab/issues/1830)) follow with the same pieces. Tracking: [#2228](https://github.com/isejalabs/homelab/issues/2228). Applications with native OIDC (Flux Operator, Proxmox) do not use this.

## How it works

```
browser ──https──► Gateway (HTTPRoute) ──► oauth2-proxy ──http──► application
                                              │   ▲
                         no session: redirect │   │ code + PKCE, token with `groups`
                                              ▼   │
                                          Keycloak (realm admin)
```

- The `HTTPRoute` of the application sends all traffic to the Service `oauth2-proxy` of its namespace. The proxy keeps the session in an encrypted cookie, sends a visitor without one to Keycloak, and lets a visitor through only if the `groups` claim of the ID token contains the group that unit allows (`sec.app.<app>.admin`, see [`ucs-groups.md`](ucs-groups.md)). Everybody else gets a 403 page.
- A `CiliumNetworkPolicy` lets only the proxy pods reach the application's pods. Without it the proxy would be a door next to an open wall: the Gateway or any pod could still talk to the application directly.
- The chart is the upstream one (`ghcr.io/oauth2-proxy/charts/oauth2-proxy`), the pieces around it are the shared kustomize component [`k8s/components/apps/oauth2-proxy`](../../k8s/components/apps/oauth2-proxy/README.md). Everything per application is in the unit of the application.

### What the component fixes

| Setting | Value | Why |
| --- | --- | --- |
| provider | `keycloak-oidc`, PKCE `S256` | the Keycloak client must have PKCE set to `S256` |
| authorization | `--allowed-group` | the group claim alone decides; `groups` is requested as a scope (`openid profile groups`) |
| user name | `--oidc-email-claim=preferred_username`, unverified e-mail allowed | accounts come from LDAP and need not have an e-mail address |
| session | encrypted cookie, 8 hours, refreshed against Keycloak every minute (`--cookie-refresh=1m`) | no Redis to run. The cookie is the proxy's own session and does not end when the Keycloak session does, which was seen in `dev`: after a logout in Keycloak the dashboard stayed open. The refresh asks Keycloak with the refresh token every minute, so a logout, a disabled account or a removed group takes effect within about a minute; `/oauth2/sign_out` ends the proxy session at once |
| `--skip-provider-button` | on | one provider only, so go straight to Keycloak |
| `--reverse-proxy` | on | build the callback URL from `X-Forwarded-Host` and `-Proto` of the Gateway |
| replicas, PDB | 1, none | a PodDisruptionBudget with one replica blocks draining the node |

## Add it to another application

The checklist for a new user; the component README has the field-level details.

1. **Group.** Name `sec.app.<app>.admin` per [`ucs-groups.md`](ucs-groups.md); creating it and adding `bob-adm` needs the owner's go (UCS).
2. **Keycloak client.** An OIDC client in the realm `admin`: confidential, PKCE on (`pkce = true`; the proxy sends `S256`), the `groups` scope as a default scope, redirect URI `https://<hostname>/oauth2/callback`, web origin the same host. Registered in the `oidc_clients` of the `keycloak-realm` unit of each environment ([`keycloak-realms.md`](keycloak-realms.md)). Terragrunt writes its client ID and secret to the 1Password item `keycloak-oidc-<app>-admin#<env>`; the `cookie-secret` is a separate hand-made item `oauth2-proxy-<app>#<env>`.
3. **Unit.** A unit `<app>-auth` (or a part of the application's own unit when it has a Flux Kustomization of its own) that includes the component, with the three Flux variables and the per-environment issuer and 1Password key patches; the `CiliumNetworkPolicy` for the application's pods; the `backendRef` of the route changed to `oauth2-proxy`. [`longhorn-auth`](../../k8s/infra/longhorn-system/longhorn-auth/) is the worked example.
4. **Machine access.** Anything that calls the application without a browser (monitoring, scripts) cannot do the login. Find it before the switch (see the inventory in [`longhorn-sso.md`](longhorn-sso.md#who-talks-to-the-ui-and-the-api)) and give it a path that does not depend on SSO: either a `skip-auth-route` for exactly the read it needs, or a separate credential ([#1714](https://github.com/isejalabs/homelab/issues/1714)). Machine access stays out of human SSO.
5. **Break-glass.** `kubectl port-forward` to the application's own Service with the cluster admin kubeconfig. It does not touch the proxy, Keycloak or the network policy. Test it once and write it into the application's page.
6. **Rollout.** `dev` first (`track-branch` while unmerged), then `qa` and `prod`; Terragrunt for `qa` and `prod` is applied from `main` only.

## Limits and things to know

- **One provider per proxy.** OAuth2 Proxy runs one OIDC provider (the alpha configuration has a `providers` list, but its documentation says multiple providers are "not yet working"). An application that must accept the realms `iseja` and `admin` both needs a second proxy on a second hostname. Every application of this pattern starts with `admin` only.
- **Authorization is coarse.** The proxy knows "in the group or not". It cannot say "may read, may not delete": a role split needs a layer behind the proxy that looks at the request, see the finding for Longhorn in [`longhorn-sso.md`](longhorn-sso.md#operator-and-read-only-for-bob-and-alice).
- **Startup needs Keycloak.** The proxy fetches the discovery document of the issuer when it starts and exits if that fails, so it restarts until Keycloak answers. An already running proxy keeps serving sessions while Keycloak is down, but cannot start a login. That is why break-glass must not go through the proxy.
- **Reserved paths.** `/oauth2/*` on the application's hostname belongs to the proxy.
- **WebSockets** pass through the proxy.
- **Gateway `ExternalAuth`** ([#1832](https://github.com/isejalabs/homelab/issues/1832)) would replace the per-application proxies once the clusters run Cilium 1.20 (`prod` runs 1.18 today); the pieces here are then removed per application, the Keycloak client stays.

## Reuse before build

Decision record for [#2228](https://github.com/isejalabs/homelab/issues/2228): the **upstream chart** (`oauth2-proxy/manifests`, OCI, Apache-2.0, maintained with every OAuth2 Proxy release; chart 10.7.2 for 7.15.6 when this was written) as an `OCIRepository`/`HelmRelease` like the other charts of the repository, instead of hand-written Deployment and Service manifests (more to keep up to date) or a remote kustomize resource (forbidden, Flux builds in the cluster). Rejected for now: Gateway `ExternalAuth` (needs Cilium 1.20), a Cilium `CiliumEnvoyConfig` basic-auth filter (owner-maintained Envoy config, no OIDC), an own nginx with `auth_request` (more code than the chart's values). The chart's `networkPolicy` option was not used: it restricts the proxy's own ingress and egress, while the policy needed here protects the application.
