---
status: planning
---

# Zigbee2MQTT web frontend: authentication approach

How the Zigbee2MQTT web frontend gets human authentication, what the deployed version offers, and how the decided design (oauth2-proxy as a plain reverse proxy plus a `CiliumNetworkPolicy`) behaves for a websocket-heavy single-page app. The investigation is [#2230](https://github.com/isejalabs/homelab/issues/2230), part of [#1767](https://github.com/isejalabs/homelab/issues/1767); the rules of the rollout are in [#2198](https://github.com/isejalabs/homelab/issues/2198), the design in [ADR 0016](../decisions/0016-identity-and-web-sso.md). The implementation is [#2231](https://github.com/isejalabs/homelab/issues/2231), the question who besides `sebi-adm` may get in is [#2232](https://github.com/isejalabs/homelab/issues/2232).

**On this page:** [Decision](#decision) · [What Zigbee2MQTT offers](#what-zigbee2mqtt-offers) · [What is deployed, who reaches the frontend](#what-is-deployed-who-reaches-the-frontend) · [How the proxy route behaves](#how-the-proxy-route-behaves) · [Is the proxy route too complicated?](#is-the-proxy-route-too-complicated) · [Roles: `sebi` and `mary`](#roles-sebi-and-mary)

## Decision

- **oauth2-proxy as a plain reverse proxy** in front of the Service, against the `admin` realm, authorized by the UCS group `sec.app.zigbee2mqtt.admin`, plus a `CiliumNetworkPolicy` that admits only the proxy to the Zigbee2MQTT pod. The shared proxy pattern is the one built for Longhorn ([#2228](https://github.com/isejalabs/homelab/issues/2228)); there is no second pattern.
- **Zigbee2MQTT's own `auth_token` stays unset.** It cannot be injected by the proxy (see below), and the network policy already closes the bypass.
- **The Gateway `ExternalAuth` route ([#1832](https://github.com/isejalabs/homelab/issues/1832)) is not needed** for this app; the reasons are in [Is the proxy route too complicated?](#is-the-proxy-route-too-complicated).
- **`sebi` and `mary` get no access** (admin only), see [Roles](#roles-sebi-and-mary).

## What Zigbee2MQTT offers

Read in the source of the deployed version, Zigbee2MQTT `2.14.2` ([`lib/extension/frontend.ts`](https://github.com/Koenkk/zigbee2mqtt/blob/2.14.2/lib/extension/frontend.ts), [`lib/util/settings.schema.json`](https://github.com/Koenkk/zigbee2mqtt/blob/2.14.2/lib/util/settings.schema.json)) and of the default UI package `zigbee2mqtt-windfront` `2.15.0` (the version pinned by that release).

| Topic | What the source says |
| --- | --- |
| Login methods | None besides `frontend.auth_token`, one shared string. No OIDC, no trusted-proxy or header option, no users or roles |
| What `auth_token` protects | Only the websocket. The HTTP server serves the static UI files without any check (`onRequest` has no authentication); `onUpgrade` compares the query parameter `token` of the websocket URL with `auth_token` and otherwise closes the socket with code `4401` |
| Where the token comes from in the browser | Windfront appends `?token=` to the websocket URL, taking it from the page URL's `token` parameter or from the browser's local storage (`z2m-token`). After a `4401` it shows a token form. A proxy cannot add a query parameter to the upgrade request, so it cannot supply the token for the user |
| Websocket endpoint | `<base_url>/api` (default `/api`), same host and port as the UI, plain HTTP upgrade; the UI derives the URL from `window.location`, so it works unchanged behind any proxy that keeps host and path |
| Origin check | None: `handleUpgrade` is called without a `verifyClient`, any `Origin` is accepted |
| What a websocket message can do | Every client message `{topic, payload}` is handed to the MQTT message handler as `<base_topic>/<topic>`, i.e. the same as an MQTT publish: `bridge/request/permit_join`, `bridge/request/restart`, `<device>/set` and so on. There is no read-only mode |
| Binding and TLS | `frontend.host`/`port` (here `0.0.0.0:8080` through `ZIGBEE2MQTT_CONFIG_FRONTEND_PORT`), optional `ssl_key`/`ssl_cert`, optional unix socket, `base_url` for a sub path, `disable_ui_serving` to serve the websocket only |
| Reconnect behaviour of the UI | After a dropped socket the UI retries ten times, then gives up until the page is reloaded |

## What is deployed, who reaches the frontend

- Runs in **`prod` only** ([README](../../k8s/apps/home-automation/zigbee2mqtt/README.md), [`environments.md`](../architecture/environments.md)): the ConBee II stick is attached to one worker. The dev registration was removed after the cut-over of [#1682](https://github.com/isejalabs/homelab/issues/1682), which is closed. `dev` and `qa` do not run the app, so the rollout cannot start in `dev` with the real application; the proxy was proven in `dev` against a stand-in (below), the real rollout is `prod` from `main`.
- The only way to the frontend is the `HTTPRoute` `zigbee2mqtt` on the internal Gateway, host `zigbee2mqtt.prod.iseja.net`, to port 8080 of the Service. There is no `frontend.auth_token` and no network policy today.
- **Home Assistant does not use the frontend.** It discovers the devices over MQTT with its own broker credentials (`zigbee2mqtt-mqtt`); `frontend.url` is not set, so Home Assistant does not link to it. A panel in the Home Assistant UI that embeds the frontend would live outside this repository; the owner should confirm none exists before the cut-over.
- The kubelet probes are TCP checks on port 8080 and are not affected by a network policy (host traffic is always admitted by Cilium).
- Nothing else in the repository or in the cluster uses the frontend (no Checkmk check, no scraper).

## How the proxy route behaves

Tested in `dev` (Cilium 1.19.9) on 2026-11-08 in a throwaway namespace: oauth2-proxy `v7.15.6` (generic `oidc` provider, `--allowed-group`, `--code-challenge-method=S256`, `--cookie-expire=3m`, `--cookie-refresh=60s`) behind the internal Gateway, a stand-in for Zigbee2MQTT that serves the real windfront UI and has the websocket and `auth_token` logic of `frontend.ts`, and a minimal OIDC provider with 90 s tokens and a `groups` claim. Real Zigbee2MQTT and the real Keycloak were not used (no coordinator in `dev`; the OIDC client support of [#2227](https://github.com/isejalabs/homelab/issues/2227) did not exist yet), so the results are about the proxy, the Gateway and the websocket, not about Keycloak.

| Check | Result |
| --- | --- |
| Unauthenticated page request | `302` to the provider |
| Unauthenticated websocket handshake | `302`, which a browser treats as a failed handshake: no socket, no data |
| Account outside the group | Callback answers `403`; websocket handshake rejected |
| Member of the group | Page `200`, websocket upgrade works through Gateway and proxy, messages flow both ways, client commands arrive at the upstream |
| Headers seen by the upstream | `Host` and `Origin` unchanged, `X-Forwarded-Proto: https`, `Connection: Upgrade`, `X-Forwarded-User`, `X-Forwarded-Groups` |
| Session cookie and tokens expire while a socket is open | **The open socket stays up**, e.g. for the full 5 minutes of the test with a 3 minute cookie and 90 s tokens. The session is checked only at the handshake |
| New socket or page request after the session is gone | Rejected (`302` to the provider), i.e. fail closed |
| Cookie refresh | Happens on an HTTP request (page load, assets) past the refresh age; a socket alone does not extend the session |
| Direct access to the Service from another namespace and from a non-proxy pod in the same namespace, with the `CiliumNetworkPolicy` | Times out; the proxy path keeps working |

What follows for the user and for the design:

- A page that stays open past the session lifetime keeps working until its socket drops. That is acceptable for this app (home network, admin realm, session length is the cookie lifetime) but is a property to know: revoking the Keycloak session does not cut an open Zigbee2MQTT page.
- When the socket drops after the session has expired, the UI retries ten times against a `302` and then stops; the user reloads the page and goes through the login again. No special handling needed.
- The proxy must be the only way in. The network policy provides that; Zigbee2MQTT's `auth_token` does not help as a second layer because the proxy cannot supply it. Making the user type it once per browser is possible (stored in local storage) but defeats the single sign-on and adds a secret to rotate, so it is not part of the design.
- Without an `Origin` check in Zigbee2MQTT, a page on another site could try to open the websocket. Browsers do not send a cookie with `SameSite=Lax` or `Strict` on a cross-site websocket handshake, so such an attempt fails at the proxy. Set `--cookie-samesite=lax` explicitly (oauth2-proxy sets no attribute by default, and not every browser defaults to `Lax`), never `none`.

## Is the proxy route too complicated?

**No.** What was checked, with the obstacles that exist and why none argues for [#1832](https://github.com/isejalabs/homelab/issues/1832):

| Possible obstacle | Finding |
| --- | --- |
| Websocket through oauth2-proxy | Works. oauth2-proxy proxies upgrades by default (`--proxy-websockets=true`), and the upgrade also works through the Cilium Gateway |
| Session expiry while a socket is open | Socket survives; new connections fail closed (above). Gateway `ExternalAuth` also decides per request, so it would behave the same |
| Zigbee2MQTT `auth_token` as a second layer injected by the proxy | Not possible with oauth2-proxy (no query rewriting). `ExternalAuth` cannot do it either: its specification lets the auth service pass headers on, and has no way to rewrite the query string. The network policy replaces it |
| `X-Forwarded-*` handling | Host, scheme and the upgrade headers arrive intact. Configure `--reverse-proxy` with `--trusted-proxy-ip` for the Gateway (the proxy logs a warning otherwise) |
| No bypass | Needs the `CiliumNetworkPolicy`; verified. With `ExternalAuth` the policy would have to admit the Gateway's ingress identity, which every route shares, so it would be weaker than admitting one proxy pod |
| Cilium version | Only the proxy route works on the `1.18.14` that `prod` runs (`dev` and `qa` run 1.19.9); nothing in the design needs more |

What moving [#1832](https://github.com/isejalabs/homelab/issues/1832) forward would cost, for the record: Cilium `prod` 1.18 → 1.19 → 1.20 (two minor upgrades, each through `dev`, `qa`, `prod`), the Gateway API CRDs on the experimental channel (the `ExternalAuth` filter is experimental) with the TLSRoute version preservation described in [#1715](https://github.com/isejalabs/homelab/issues/1715), and an authentication service for the filter to call, which is oauth2-proxy again in `auth_request` mode, so no proxy is saved. It gains nothing for Zigbee2MQTT: the same checks happen at the same moment (the handshake), the bypass protection gets weaker and the app gets no extra capability. If it is wanted for other reasons (consolidating the per-app proxies of Longhorn, Zigbee2MQTT and AdGuard into one), it can follow later without redoing the Keycloak side.

## Roles: `sebi` and `mary`

Expected outcome of [#2232](https://github.com/isejalabs/homelab/issues/2232): **no access for `sebi` and `mary`**, decided from the same source reading:

- There is no read-only mode: every websocket message becomes an MQTT publish (see the table above), including `bridge/request/restart`, `permit_join` and device `set` commands. A UI that "only looks" is not an enforced restriction.
- A proxy cannot filter it: oauth2-proxy authenticates the upgrade request and then relays frames without looking at them; method and path rules see `GET /api` for read and write alike. Filtering frames would need a custom websocket-aware proxy, which is a new component to maintain for a UI used by one person.
- A second realm provider on the proxy would therefore only widen access without any read-only guarantee.

Consequently only `sec.app.zigbee2mqtt.admin` exists; no `operator` or `readonly` group is created in UCS.
