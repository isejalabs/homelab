---
status: current
---

# Longhorn human SSO

The Longhorn dashboard sits behind a login from the Keycloak realm `admin`: an [OAuth2 Proxy](oauth2-proxy.md) in front of the UI, and a network policy that lets nothing reach the UI around it. Tracking: [#1725](https://github.com/isejalabs/homelab/issues/1725) (parent), [#2228](https://github.com/isejalabs/homelab/issues/2228) (`bob-adm`), [#2229](https://github.com/isejalabs/homelab/issues/2229) (`bob` and `alice`). Rules of the rollout: [#2198](https://github.com/isejalabs/homelab/issues/2198). The unit is [`longhorn-auth`](../../k8s/infra/longhorn-system/longhorn-auth/README.md).

**Status (2026-11-10):** running and verified in `dev` (merged 2026-11-09, [#2244](https://github.com/isejalabs/homelab/pull/2244)) and `qa` (merged 2026-11-10, [#2266](https://github.com/isejalabs/homelab/pull/2266), [#2267](https://github.com/isejalabs/homelab/pull/2267)), and `prod` (merged 2026-11-10, [#2268](https://github.com/isejalabs/homelab/pull/2268), [#2270](https://github.com/isejalabs/homelab/pull/2270)). All three environments run the login; the dashboards of `dbg`, `head`, `poc`, `src` and `rebuild` stay without one. The Keycloak clients `longhorn` (realm `admin`) and the UCS group `sec.app.longhorn.admin` exist. Details and the open steps are in [Rollout](#rollout).

## Before: how Longhorn was exposed

Checked live in `dev` on 2026-11-08.

- The `HTTPRoute` `longhorn` in `longhorn-core` sends `/` of the hostname to the Service `longhorn-frontend` (port 80, the `longhorn-ui` pod, nginx on 8000) through the `internal` Gateway: reachable from the LAN, no login. Hostnames: [`longhorn-core`](../../k8s/infra/longhorn-system/longhorn-core/README.md#access).
- The UI's nginx forwards every `/v1/*` to the manager API `longhorn-backend:9500`, so reaching the UI means the whole API with its mutating actions (attach, detach, delete, settings, disk updates).
- A throwaway pod in the namespace `default` got `200` for `GET http://longhorn-frontend.longhorn-system.svc/v1/nodes`, and a timeout for `http://longhorn-backend.longhorn-system.svc:9500/v1/nodes`. The chart ships a Kubernetes `NetworkPolicy` `longhorn-manager` that admits only the Longhorn pods (manager, UI, CSI plugin, driver deployer, recurring-job pods) to the manager, so the API was only open through the UI.
- The cluster runs Cilium with Kubernetes network policy enforcement on (`enable-k8s-networkpolicy`), `dev` and `qa` on 1.19, `prod` on 1.18.

## Who talks to the UI and the API

| Caller | Path | Needs credentials today | After the switch |
| --- | --- | --- | --- |
| Browser of a human | route → UI → `/v1` | no | login (this page) |
| Checkmk special agent `longhorn_capacity` ([`checkmk-modules`](https://github.com/isejalabs/checkmk-modules/tree/main/packages/longhorn_capacity)), `dev`, `qa`, `prod` | `GET http://<longhorn hostname>/v1/nodes` (the plain-HTTP URL redirects to HTTPS) through the route | no, it sends none | `skip-auth-route: GET=^/v1/nodes$`, unchanged URL; replaced by a credential in [#1714](https://github.com/isejalabs/homelab/issues/1714) |
| Longhorn components (UI, CSI plugin, driver deployer, managers, recurring jobs) | `longhorn-backend:9500`, in-cluster | no | unchanged, they never use the route |
| kopiur, the `scripts/ops/longhorn` scripts, the repository's other tooling | Kubernetes API on the `*.longhorn.io` custom resources and `VolumeSnapshot`s, not the Longhorn API | Kubernetes RBAC | unchanged |
| Prometheus | the repository runs no monitoring stack ([`monitoring.md`](../architecture/monitoring.md)) | | |

Searched in the repository for `longhorn-frontend`, `longhorn-backend` and port 9500; nothing else calls them. The skipped path leaves exactly the one unauthenticated read the agent needs; every other path, including `POST`, needs the login. It reveals node and disk capacity to the LAN, as before, and goes when [#1714](https://github.com/isejalabs/homelab/issues/1714) gives the agent its own credential.

## After: the pieces

| Piece | Where |
| --- | --- |
| Proxy: `HelmRelease` `oauth2-proxy` in `longhorn-system`, realm `admin`, allowed group `sec.app.longhorn.admin` | [`longhorn-auth`](../../k8s/infra/longhorn-system/longhorn-auth/) with the [component](../../k8s/components/apps/oauth2-proxy/README.md) |
| `CiliumNetworkPolicy` `longhorn-ui-only-from-oauth2-proxy`: UI pods accept TCP 8000 from the proxy pods only | [`longhorn-auth/base/networkpolicy.yaml`](../../k8s/infra/longhorn-system/longhorn-auth/base/networkpolicy.yaml) |
| Route: `backendRef` `longhorn-frontend` → `oauth2-proxy` | `envs/<env>/http-route-oauth2-proxy.yaml` in [`longhorn-core`](../../k8s/infra/longhorn-system/longhorn-core/envs/dev/http-route-oauth2-proxy.yaml), per environment that runs the proxy |
| Keycloak client `longhorn` in `admin` | `oidc_clients` of the `keycloak-realm` unit ([#2227](https://github.com/isejalabs/homelab/issues/2227)) |
| Secret `oauth2-proxy` (client ID, client secret, cookie secret) | 1Password items `keycloak-oidc-longhorn-admin#<env>` (written by Terragrunt: username = client ID, password = client secret) and `oauth2-proxy-longhorn#<env>` (field `cookie-secret`), External Secrets |
| UCS group `sec.app.longhorn.admin` with `bob-adm` | UCS, owner's go needed ([`ucs-groups.md`](ucs-groups.md)) |

The policy is the first `CiliumNetworkPolicy` of the repository; the model for the others is [#1995](https://github.com/isejalabs/homelab/issues/1995). It is deliberately narrow: it selects only the UI pods, so nothing else changes behaviour. The manager API stays protected by the chart's own `NetworkPolicy`, and only the UI (now behind the proxy) can reach it from outside Longhorn.

kubelet probes and `kubectl port-forward` are meant not to be affected (host and loopback traffic); **verify this in `dev` with the policy applied** (an open item below).

## Break-glass

The dashboard without Keycloak, UCS, the proxy or the Gateway; needs only the cluster admin kubeconfig:

```sh
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80 --context admin@<env>-homelab
# then http://localhost:8080
```

This goes to the UI pod directly and is the one unauthenticated way in; it is as protected as the kubeconfig. **Not yet tested with the policy applied** (open item below). The proxy needs Keycloak to start ([`oauth2-proxy.md`](oauth2-proxy.md#limits-and-things-to-know)), and Keycloak's database lives on a Longhorn volume, so a cluster-wide storage failure cannot be fixed through a login that depends on it: this path exists for exactly that.

## MFA

The realm `admin` is where the WebAuthn second factor is introduced ([#2206](https://github.com/isejalabs/homelab/issues/2206)); the proxy only receives the ID token after Keycloak has run the realm's browser flow, so whatever that flow demands also applies to the Longhorn login. In `dev`, `qa` and `prod` the owner logged in as `bob-adm` (2026-11-09 and 2026-11-10). The login page of the realm `admin` offers a passkey and TOTP (whichever is enrolled for the account); the passkey was used in `dev`. The proxy asks Keycloak again every minute (`--cookie-refresh=1m`), so the lifetime of the Keycloak session, not the 8-hour cookie, decides how long access lasts; a logout in Keycloak ended access within a minute or two. The Keycloak session lifetime of the realm was not read and is not recorded here; it is a setting of the realm (see [`keycloak-mfa.md`](keycloak-mfa.md)).

## Operator and read-only for `bob` and `alice`

Question of [#2229](https://github.com/isejalabs/homelab/issues/2229): can the dashboard be offered to `bob` (operator) and `alice` (read-only), or do they get no access. Findings, from the API schema of the running Longhorn 1.13.0 in `dev` (`GET /v1/schemas`) and the UI bundle:

- **The API has 97 resource types; mutation is `POST`, `PUT` and `DELETE`**: 8 types accept `POST` on the collection, 5 accept `PUT`, 10 accept `DELETE`, and 58 actions (`POST …?action=<name>`) sit on volumes, backup volumes, backup targets, backing images and nodes.
- **A method filter alone does not give a working read-only view.** Several actions the UI needs just to *show* data are `POST` actions: `snapshotList`, `snapshotGet`, `snapshotCRList`, `snapshotCRGet`, `jobList`, `recurringJobList`, `backupList`, `backupGet` and `backupListByVolume` (the UI bundle calls `action=backupList`). Blocking all `POST` empties the snapshot and backup pages of a volume.
- **An allow-list of safe actions is technically possible** (the action name is in the query string; Gateway API `HTTPRoute` rules can match method and query parameters, Cilium L7 policy cannot match the query). But it cannot sit inside the proxy: OAuth2 Proxy decides per login, not per request, and passing the group to a second hop would need an own nginx or Envoy layer. An operator role ("harmless permissions only", for example `snapshotCreate` and `snapshotBackup` but not `volume` delete or `diskUpdate`) is the same list again, with a second list per role.
- **The realms.** `bob` and `alice` are in `iseja`, `bob-adm` in `admin`, and a proxy runs one provider ([`oauth2-proxy.md`](oauth2-proxy.md#limits-and-things-to-know)). Their access therefore needs a second proxy instance, a second hostname and a second Keycloak client, with its own allow-list layer behind it.
- **The list would age.** It must be kept in step with every Longhorn release (new actions, a new read-only `POST`); a missing entry is a harmless broken page, but a wrongly added one is a hole nobody notices.

**Decision (owner, 2026-11-09):** `bob` and `alice` get **no access** to the Longhorn dashboard; `bob-adm` is the only account. Reasons: no role separation exists in Longhorn, a reliable one would be a second proxy plus an own request filter with a per-release maintenance cost, and the protected asset (the storage layer of the cluster) is operated by the administrator anyway. Revisit if a real need appears; the sketch above is the starting point, and the UCS groups `sec.app.longhorn.operator` and `sec.app.longhorn.readonly` of [#2229](https://github.com/isejalabs/homelab/issues/2229) are then created. They do not exist now.

## Rollout

| Step | State |
| --- | --- |
| Manifests: component, `longhorn-auth`, policy, route patch for `dev` | written, builds for all 8 environments (`kubectl kustomize`) and `flate test` for `dev` passes; not applied |
| OIDC client in `dev` | done 2026-11-09: `oidc_clients` entry `longhorn-admin` in the `dev` unit (module `keycloak-realm-v0.6.0`), applied from the branch with `-target` on the three new resources (client, default scopes, 1Password item `keycloak-oidc-longhorn-admin#dev`). The plan of the whole unit also shows 4 destroys: the leftover test clients `checkmk-prod-test-admin` and `-iseja` that are in the `dev` state but not in the configuration. Targeting the module also destroyed their two 1Password items (`keycloak-oidc-checkmk-prod-test-*#dev`); the clients and their Keycloak secrets are untouched |
| UCS group `sec.app.longhorn.admin` and `bob-adm` as member | done 2026-11-09 on the master `adelheid` with the owner's go (`udm groups/group create`, then `--append users=uid=bob-adm,...`; `udm` lists `bob-adm` as the only member). Not yet checked in Keycloak after the group sync |
| Live test in `dev`, no login needed (2026-11-09) | passed: unauthenticated `GET /` → 302 to `dev-auth.dev.iseja.net/realms/admin/...` with `client_id=longhorn` and a PKCE challenge; `GET /v1/volumes`, `GET /v1/nodes/x` and `POST /v1/nodes/x?action=diskUpdate` without a session → 302 to the login; `GET /v1/nodes` (also via the plain-HTTP URL, which redirects to HTTPS) → 200 for the Checkmk agent; from a pod in `default`: `longhorn-frontend` → timeout, `longhorn-backend:9500` → timeout, the proxy Service answers (302 for `/v1/volumes`, 200 for `/v1/nodes`); the UI pod stays Ready with 0 restarts; `kubectl port-forward svc/longhorn-frontend` → 200 on `/` and `/v1/volumes` with the policy applied |
| First login attempt in `dev` (2026-11-09) | `bob-adm` passed Keycloak (passkey) and the proxy answered 403: the log shows `AuthFailure ... unauthorized` for `bob-adm`. Cause: Keycloak had cached the user with his old groups (`sec.app.checkmk.admin` only), although the group sync had imported `sec.app.longhorn.admin` and listed him as a member. `POST /admin/realms/admin/clear-user-cache` (204) fixed it: the example ID token for the client then carries `groups: [sec.app.checkmk.admin, sec.app.longhorn.admin, sec.app.proxmox.admin]`. **A new membership in a UCS group is not seen by a cached user until the user cache is cleared or expires**, so after adding someone to a `sec.app.*` group clear the user cache of the realm (or wait) before the first login |
| Live test in `dev`, login (2026-11-09) | passed, reported by the owner: `bob-adm` logs in through the realm `admin` with his passkey and reaches the dashboard (after the user cache was cleared, see the row above). `bob-adm` was denied with the 403 page before the group was visible to Keycloak, which shows an account outside `sec.app.longhorn.admin` is refused; a second `admin`-realm account to test with does not exist. After a logout in Keycloak the dashboard stayed open on the proxy's own 8-hour cookie; with `--cookie-refresh=1m` the owner confirmed that access ends within a minute or two of a Keycloak logout. The groups claim is checked on the example ID token: `sec.app.checkmk.admin`, `sec.app.longhorn.admin`, `sec.app.proxmox.admin` |
| `qa` (2026-11-10) | done: client applied from `main` (3 added, plan clean afterwards), 1Password items `keycloak-oidc-longhorn-admin#qa` and `oauth2-proxy-longhorn#qa`, group sync run and user cache cleared (the example ID token holds `sec.app.longhorn.admin` for `bob-adm`), route patch and registration merged. Checks without a login as in `dev`: `GET /` → 302 to `qa-auth.qa.iseja.net/realms/admin`, `GET /v1/volumes` and `POST …?action=diskUpdate` → 302, `GET /v1/nodes` → 200 (also via plain HTTP), a pod in `default` times out on `longhorn-frontend` and `longhorn-backend:9500`, UI pod Ready with 0 restarts, port-forward → 200. The owner confirmed the `bob-adm` login with his passkey |
| `prod` (2026-11-10) | done: client applied from `main` (3 added, plan clean afterwards), 1Password items `keycloak-oidc-longhorn-admin#prod` and `oauth2-proxy-longhorn#prod`, group sync run and user cache cleared, route patch and registration merged. Checks without a login as in `dev` and `qa`, on Cilium 1.18: `GET /` → 302 to `auth.iseja.net/realms/admin`, `GET /v1/volumes` and `POST …?action=diskUpdate` → 302, `GET /v1/nodes` → 200 (also via plain HTTP), a pod in `default` times out on `longhorn-frontend` and `longhorn-backend:9500`, UI pod Ready (its 2 restarts date from 2026-10-15), port-forward → 200. The owner confirmed the `bob-adm` login |

`dbg`, `head`, `poc`, `src` and `rebuild` keep the unprotected route: there is no client for them (the on-demand environments register in `prod`'s Keycloak, `rebuild` has no realm unit), and a proxy without a client would take the dashboard away.
