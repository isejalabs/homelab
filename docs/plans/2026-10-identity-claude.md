# Identity and web SSO — independent design pass

**Date:** 2026-10-21. **Status:** Independent second pass; reviewed by the owner on 2026-10-21, see [Owner review](#owner-review-2026-10-21) for what is accepted and what changed. **Builds on:** umbrella [#1715](https://github.com/isejalabs/homelab/issues/1715), its sub-issues, and the planning ADR [0016](../decisions/0016-identity-and-web-sso.md) from [PR #1724](https://github.com/isejalabs/homelab/pull/1724). Those were read, but not taken as given: every point where this pass reaches a different conclusion is listed in [Differences from the first pass](#differences-from-the-first-pass) with a recommendation and the decision it needs. The accepted result is recorded by rewriting [ADR 0016](../decisions/0016-identity-and-web-sso.md) in place.

Like the first pass, this was produced from repository evidence, issue history, and vendor documentation. Nothing was checked live; the [Phase 0](#phase-0--live-inventory) inventory is still the gate before anything is built.

## Summary

- **Select the IdP now: upstream Keycloak, run in Kubernetes, federating UCS read-only.** It is the only candidate that covers OIDC, SAML, LDAP/AD federation, Kerberos SPNEGO, conditional MFA and passkeys in one product, and it is the IdP inside Nubus, so it is also the migration path. The live UCS inventory changes integration details, not this choice.
- **Two realms, not one:** an everyday realm (`iseja`) with Kerberos SPNEGO for `sebi` and family, and an admin realm (`admin`) for `*-adm` accounts only, no Kerberos, UCS password plus a WebAuthn authenticator (passkey or YubiKey), TOTP as fallback. This is what makes `sebi` and `sebi-adm` work side by side in one browser.
- **Decouple from Cilium 1.20.** Native OIDC covers most services; the two or three that have no auth of their own (Longhorn, Zigbee2MQTT, AdGuard) get oauth2-proxy as a plain reverse proxy, which works on the Cilium 1.18 that `prod` runs today. Gateway `ExternalAuth` becomes an optional later consolidation, not a prerequisite.
- **Placement is a design decision the first pass skipped:** the authoritative IdP runs in `prod`; `qa` runs its own instance as the upgrade gate; `rebuild` runs one to rehearse IdP recovery; other non-prod environments use the `prod` IdP (non-prod depending on prod is the acceptable direction).
- **Availability is concrete, not open:** 2 Keycloak replicas, CloudNativePG with 1 instance (2 optional), sessions persisted in the database, nightly database backups to S3, realm configuration in Git. Target: 1 h to restore, at most 24 h of MFA enrollments lost. Every core infrastructure service keeps a local login that does not depend on the IdP, Kubernetes, or UCS.

## Inputs

The owner's brief (paraphrased): UCS on `adelheid` (pve1) and `baerbel` (pve5) provides DHCP, DNS for `dir.iseja.net` and `10.7.0.0/16`, LDAP, Kerberos, AD and SAML (`ucs-sso.dir.iseja.net`); `adelheid` hangs from time to time. Nubus is the long-term wish but cannot replace UCS network services. Keycloak on UCS was tried as a PoC; it was not HA-capable without a shared PostgreSQL, and it is ClickOps. A PostgreSQL cluster is not required; failover plus a replicated Longhorn volume is enough. Services: Longhorn, Flux Operator, Zigbee2MQTT, Immich, Checkmk, Proxmox, RustFS, OPNsense, TrueNAS, and more. Core services may keep local login. 2FA for web apps; ideally real SSO from the OS Kerberos login on macOS and Windows; keep the `sebi` / `sebi-adm` split.

Repository and issue facts that shape the design:

- 8 environments; `prod` (3+3 nodes, Let's Encrypt production) is the only HA cluster. `qa`, `dev`, and `rebuild` also use Let's Encrypt production; `dbg`, `head`, `poc`, and `src` use staging ([`docs/architecture/environments.md`](../architecture/environments.md), `k8s/infra/cert-manager/cert-manager/envs/*/cluster-issuer.yaml`).
- Cilium 1.18 in `prod`/`poc`, 1.20 in `head`; Gateway API 1.4.1 CRDs ([`docs/architecture/network.md`](../architecture/network.md), [#1715](https://github.com/isejalabs/homelab/issues/1715)).
- Browser-facing `HTTPRoute`s today: Flux Operator UI, Longhorn UI, whoami, actualbudget, checkmk-agent, AdGuard, Zigbee2MQTT. Hubble UI is disabled.
- UCS stability is its own open workstream: [#1813](https://github.com/isejalabs/homelab/issues/1813) (adelheid hangs), [#1816](https://github.com/isejalabs/homelab/issues/1816) (both DCs have 2.5 GB RAM), [#1817](https://github.com/isejalabs/homelab/issues/1817), [#1818](https://github.com/isejalabs/homelab/issues/1818), [#1821](https://github.com/isejalabs/homelab/issues/1821) (redundancy of DNS/DHCP/LDAP on one DC).
- Out-of-cluster configuration is already managed as code through Terragrunt units (for example `terragrunt/prod/eu-central-1/prod/checkmk-longhorn-monitoring/`, ADR 0015).

## Differences from the first pass

Each row is a point to confirm or reject. "First pass" means ADR 0016 in [PR #1724](https://github.com/isejalabs/homelab/pull/1724) plus the [#1715](https://github.com/isejalabs/homelab/issues/1715) body and comment.

| # | Topic | First pass | This pass (recommendation) | Decision needed |
| --- | --- | --- | --- | --- |
| D1 | IdP selection | Deferred until after UCS inventory; Keycloak, Nubus "and other candidates" to be evaluated | **Select Keycloak now.** The hard requirements (OIDC + SAML + LDAP/AD federation + Kerberos SPNEGO + conditional MFA) leave two products: Keycloak and authentik (Kerberos source with SPNEGO). Authelia, Zitadel, Kanidm, Pocket ID lack SPNEGO. Keycloak wins on Nubus alignment (Nubus *is* Keycloak plus UCS extensions), maturity of its Kerberos/LDAP federation, an official operator and an official OpenTofu provider. The inventory decides *how* to federate, not *which* IdP. | Accept Keycloak as the IdP |
| D2 | Gateway `ExternalAuth` | Central pattern for browser apps; proof in `poc` gated on Cilium 1.18 → 1.19 → 1.20 and Gateway API 1.6.1 CRDs; part of #1715 acceptance | **Not on the critical path.** Only Longhorn, Zigbee2MQTT and AdGuard lack native SSO. oauth2-proxy as a reverse proxy in front of each (plus a `CiliumNetworkPolicy` that only admits the proxy) works on today's Cilium. Flux Operator's UI has **native** OIDC with Kubernetes impersonation, so it does not need a gateway filter. Keep the `ExternalAuth` proof as its own optional issue, done when Cilium 1.20 reaches `prod` for its own reasons. | Move the `ExternalAuth` proof out of #1715 acceptance |
| D3 | IdP placement across environments | Not addressed | `prod` hosts the authoritative IdP, also for Proxmox, OPNsense, TrueNAS, RustFS, Checkmk. `qa` runs its own Keycloak (upgrade and config gate), `rebuild` runs one (rehearses restore). `dbg`/`dev`/`head`/`poc`/`src` register their UIs as clients in the `prod` IdP. One codebase, deployed with the usual `base/` + `envs/` overlays. | Confirm placement, and that non-prod may depend on `prod` |
| D4 | `sebi` / `sebi-adm` | "Preserve separate identities, map groups" | **Two realms.** A browser holds one SSO session per realm, and SPNEGO always presents the OS user's ticket (`sebi`), so a single realm cannot give both identities SSO at once: logging in as `sebi-adm` would replace `sebi`'s session. With `iseja` (everyday, Kerberos) and `admin` (`*-adm` only, passkey, no Kerberos), both sessions coexist. Admin UIs trust only `admin`; everyday apps trust only `iseja`. Kerberos SSO for `sebi-adm` is not possible from a `sebi` OS login; SSO across admin apps after one passkey login per day is. | Accept two realms |
| D5 | MFA with Kerberos | "Require MFA; Kerberos must not silently bypass it" (no policy chosen) | `iseja`: a valid Kerberos ticket from a domain-joined device counts as sufficient (device + OS password); any password login requires a second factor (passkey or TOTP). `admin`: passkey (WebAuthn) always, TOTP only as a fallback credential. Requiring OTP *on top of* Kerberos is possible in Keycloak but removes the SSO benefit; offer it per client via a step-up level (`acr`) instead of globally. | Is Kerberos-from-a-domain-device acceptable as strong enough for everyday apps? |
| D6 | Availability target | "Define an acceptable outage"; no numbers | Concrete proposal in [Availability and recovery](#availability-and-recovery): 2 Keycloak replicas, CloudNativePG 1 instance (2 optional), persisted sessions, nightly backups to RustFS, RTO 1 h, RPO 24 h for MFA enrollments. | Accept the targets |
| D7 | Database | "A single instance on recoverable storage remains an option" | Use **CloudNativePG**, even with 1 instance: it brings scheduled base backups and WAL archiving to S3, point-in-time restore, and a one-line switch to 2 instances. A plain PostgreSQL StatefulSet would need all of that hand-built. | Accept CloudNativePG |
| D8 | Configuration as code | "Repository-owned IaC/GitOps" (no tool) | Keycloak server via the **Keycloak Operator** (Flux). Realm content (realms, LDAP federation, flows, clients, mappers) via the **`keycloak/keycloak` OpenTofu provider** in Terragrunt units, the same pattern already used for Checkmk. The provider can also create the Proxmox OIDC realm in the same plan. `KeycloakRealmImport` is not suitable: it only creates, it never updates. | Choose Terragrunt/OpenTofu for realm content (vs. keycloak-config-cli as a Flux Job) |
| D9 | Keycloak PoC on UCS | "Needs to be removed if unused" | **Inventory before removing.** On UCS 5.2 the Univention Keycloak app *is* the default SAML IdP (SimpleSAMLphp is gone), so `ucs-sso` / `ucs-sso-ng` and the portal/UMC login may depend on what looks like the PoC. Remove only the parts proven unused, in its own issue. UCS DCs with 2.5 GB RAM ([#1816](https://github.com/isejalabs/homelab/issues/1816)) are a further reason not to run the new IdP there. | New sub-issue for the removal |
| D10 | UCS as dependency | Not discussed | LDAP federation lists both DCs (`ldaps://baerbel… ldaps://adelheid…`, Keycloak fails over sequentially); `baerbel` first while `adelheid` is unstable. Users are imported and synced, so Keycloak keeps profiles, groups and MFA credentials during a UCS outage, but password and Kerberos validation still need a DC. Hence the UCS stability issues are a soft prerequisite. | — |
| D11 | Service matrix | Every service "evaluate native vs `ExternalAuth`" | Verified capabilities change several sub-issues: OPNsense and TrueNAS have no OIDC/SAML login → keep local + TOTP, decide then on LDAP only; Checkmk SAML exists only in the commercial editions → depends on the edition; RustFS console has native OIDC; Proxmox has a native OIDC realm with group claims. See [Service matrix](#service-matrix). | Review the per-service rows |
| D12 | Services missing from the list | Ten services | Add: actualbudget (native OIDC), AdGuard (oauth2-proxy or keep local), UniFi controller (local only), UCS portal/UMC itself, Home Assistant (no native OIDC; keep local with its own MFA). | Which of these get sub-issues |
| D13 | Kubernetes API (#1766) | OIDC + RBAC, break-glass | Agree. Add: use Talos's structured authentication configuration (several issuers, claim rules, no API-server restart on change); bind cluster-admin only to groups from the `admin` realm; break-glass is the Talos-issued admin kubeconfig (`talosctl kubeconfig`), which never depends on the IdP. | — |

### Owner review 2026-10-21

| # | Outcome | Clarification or change from the review |
| --- | --- | --- |
| D1 | Accepted, made explicit | The choice is **Keycloak in Kubernetes** (placement in D3). Keycloak on UCS is rejected as the IdP: it is the same Keycloak, but ClickOps, on DCs short of memory ([#1816](https://github.com/isejalabs/homelab/issues/1816)), next to an unstable `adelheid`, and it would still need an external PostgreSQL for shared state. A Univention Keycloak on UCS is only relevant for UCS's *own* portal/UMC SAML login; see D9. |
| D2 | Accepted | — |
| D3 | Accepted | — |
| D4 | Accepted, refined | Realm names: `admin` confirmed; the everyday realm (working name `home` in this pass) is named **`iseja`**, matching the AD domain `ISEJA`. Keycloak realm names are local to one instance, so every environment reuses both names. The `admin` realm accepts any **WebAuthn** authenticator (passkey in 1Password, YubiKey, platform authenticator) as the second factor, with **TOTP as a fallback**. Keep it *password (UCS) + WebAuthn*, not passwordless: the UCS password check keeps UCS authoritative for locking or disabling an account. Trade-off to know: if the `sebi-adm` password, passkey and TOTP seed all live in 1Password, the factors collapse into "access to the vault"; a YubiKey enrolled as an additional authenticator keeps one factor outside it. |
| D5 | Accepted, rationale corrected | The earlier wording overstated it: a Kerberos ticket is **not** bound to a domain-joined device. Anyone who can reach a KDC (TCP/UDP 88) can run `kinit` with the password and then use SPNEGO, so in practice Kerberos SSO means "password only". Compensating controls, all in the Kerberos/MFA sub-issue: (1) restrict KDC ports on OPNsense to the managed-client and server VLANs; (2) inventory remote access that yields a ticket or a password prompt (SSH on UCS, TrueNAS and other Linux hosts → key-only; RDP on Windows → off or restricted); (3) apps holding sensitive data (actualbudget, later others) request a higher level (`acr`) and get a second factor even after Kerberos. |
| D6/D7 | Accepted ("start small, think big, scale fast") | Start with 1 PostgreSQL instance; the scale-up is `instances: 2`, a one-line change. Database outage and maintenance behaviour is spelt out in [Availability and recovery](#availability-and-recovery). |
| D8 | Accepted | — |
| D9 | Accepted, extended | The PoC on UCS was never used and can go. Whether UCS's portal/UMC login should use SAML at all, and against which IdP (a properly installed Univention Keycloak app on UCS, or the Kubernetes Keycloak as an external SAML IdP), is a separate question in the removal issue; until then UMC keeps its own login. |
| D10 | Noted | Both DCs serve every role, including synced TLS certificates on `baerbel`; the details are verified in [#1821](https://github.com/isejalabs/homelab/issues/1821). |
| D11 | Accepted, reframed | Each service gets a target on a three-level scale, see [Integration levels](#integration-levels). TrueNAS already authenticates against AD (level 1, no OTP). |
| D12 | Accepted, changed for Home Assistant | No native OIDC is not the end: each such app gets an investigation of alternatives (for Home Assistant, community/HACS OIDC integrations or a header-auth proxy), weighed against the risk of a third-party auth component. |
| D13 | Accepted | — |

Points where this pass agrees with the first pass without change: UCS stays authoritative for users and groups; no new Keycloak on UCS; prefer native OIDC; machine and monitoring credentials stay separate ([#1714](https://github.com/isejalabs/homelab/issues/1714)); Longhorn replicas are not database HA; local break-glass for core infrastructure.

## Target architecture

```
                      UCS (authoritative: users, groups, Kerberos, DNS, DHCP)
                      baerbel (pve5) ── adelheid (pve1)
                         │ LDAPS (read-only bind)      │ KDC (keytab for HTTP/auth.iseja.net)
                         ▼                             ▼
   ┌──────────────── prod cluster ──────────────────────────────────────────┐
   │  Keycloak (Operator, 2 replicas) ── CloudNativePG (1–2 instances)       │
   │     realm "iseja": LDAP filter = everyday users, Kerberos SPNEGO,       │
   │                    password → 2nd factor                                │
   │     realm "admin": LDAP filter = *-adm in group idm-admins,             │
   │                    password + WebAuthn (TOTP fallback), no Kerberos      │
   │  Backups: CNPG → RustFS (S3); realm config → Git (OpenTofu)              │
   └─────────────────────────────────────────────────────────────────────────┘
        │ OIDC                         │ OIDC                    │ OIDC (oauth2-proxy)
        ▼                              ▼                         ▼
   iseja realm clients            admin realm clients        browser-only apps
   Immich, actualbudget          Flux UI, K8s API, Proxmox, Longhorn (admin),
   (+ mobile apps)               RustFS, Checkmk*           Zigbee2MQTT (iseja), AdGuard

   Local break-glass (never via IdP): Proxmox root@pam, OPNsense root, TrueNAS admin,
   RustFS root user, Checkmk cmkadmin, talosctl admin kubeconfig.
```

### Hostname and certificates

One stable issuer hostname per instance, for example `auth.iseja.net` (prod) and the prefixed equivalents elsewhere through `prefix-domain`. It must be an **A record, not a CNAME**: Kerberos clients canonicalize names, and a CNAME makes browsers request a ticket for the wrong service principal. The issuer stays the same if the implementation later changes (Nubus), so clients do not need re-registration. Let's Encrypt production certificates are required wherever native mobile apps (Immich) or the Kubernetes API server validate the issuer.

### Identity and group model (in UCS)

Authorization stays in UCS groups, so there is one place to grant and audit access:

- `idm-users`: everyday accounts allowed into the `iseja` realm (family included).
- `idm-admins`: `*-adm` accounts only; the `admin` realm's LDAP filter admits nothing else.
- Per-app role groups, for example `app-immich-users`, `app-longhorn-admins`, `app-proxmox-admins`, `app-k8s-admins`, `app-k8s-viewers`. Keycloak passes them in a `groups` claim; each app maps them to its roles.

`sebi` is in `idm-users`; `sebi-adm` is in `idm-admins` plus the admin app groups. Nobody is in both realms' filters with the same account.

### Kerberos SPNEGO

- Create a UCS service account and register the SPN `HTTP/auth.iseja.net@DIR.ISEJA.NET`; export its keytab to 1Password; deliver it to Keycloak with External Secrets.
- Configure Kerberos on the `iseja` realm's LDAP provider (Kerberos principal attribute `userPrincipalName` or `uid@REALM`, verified against UCS in Phase 0).
- Clients: Windows (domain-joined to UCS Samba AD) needs the host in the Local Intranet zone via GPO; Chrome/Edge on macOS need `AuthServerAllowlist` (configuration profile); Safari on a domain-bound Mac uses the login ticket; Firefox needs `network.negotiate-auth.trusted-uris`. Phones and non-domain devices fall back to password + second factor.
- Verify in Phase 0 how the Macs obtain a ticket today (AD binding, Kerberos SSO extension, or `kinit`).

## Availability and recovery

| Failure | Effect | Recovery |
| --- | --- | --- |
| One Keycloak pod | None; the other replica serves, sessions are in the database | Automatic |
| PostgreSQL pod / node | Logins fail until CNPG reschedules the instance on its Longhorn volume (minutes) | Automatic; with 2 instances, CNPG fails over |
| Database lost | Realm config comes back from Git; users re-sync from UCS; **MFA enrollments and sessions are lost** unless restored | CNPG restore from the RustFS backup (target RTO 1 h, RPO 24 h) |
| `adelheid` down | None if `baerbel` is listed first in LDAP and the krb5 KDC list | Automatic |
| Both DCs down | No new logins for UCS-backed users; existing sessions continue | Local break-glass on core services |
| `prod` cluster down | Every SSO login fails, including non-prod UIs | Local break-glass on Proxmox, OPNsense, TrueNAS, RustFS; `talosctl` for Kubernetes |
| RustFS down | Backups fail (alert), logins unaffected | — |

### What still works while the database is unavailable

Each application keeps its **own** session once an OIDC login has completed; it only talks to Keycloak again for a new login, a token refresh, or logout. Treat Keycloak as down while its database is down: Keycloak 26 keeps user sessions in the database (with an in-memory cache in front), and creating or refreshing a session writes to it.

| Situation during a database outage | Expected result |
| --- | --- |
| `sebi-adm` already logged in to Checkmk `prod` | Keeps working until Checkmk's own session expires |
| `sebi-adm` opens a second app (Flux UI, Longhorn) for the first time | Fails: needs a new authorization at Keycloak, even though the SSO cookie exists |
| `kubectl` with a still-valid ID token (kubelogin cache) | Works: the API server checks the token signature against cached keys, without calling Keycloak |
| `kubectl` after the ID token expired | Fails until Keycloak is back; use the break-glass kubeconfig |
| App that refreshes access tokens in the background (Immich mobile) | Fails at the next refresh |

These are expectations from how OIDC and Keycloak work, not measurements. Phase 1 acceptance includes stopping the database on purpose and recording what actually happens.

### Node reboots and cluster upgrades

With one PostgreSQL instance, CloudNativePG refuses to let a node drain while its instance runs there, because a single instance cannot switch over. Two ways to handle it:

- **1 instance:** set `enablePDB: false` (CloudNativePG's documented setting for single-instance clusters). The drain then evicts the pod, and it restarts on another node with a Longhorn replica: about 1–3 minutes without new logins per node that hosts it, accepted for this phase.
- **2 instances (scale-up):** the drain triggers a switchover to the replica in seconds, and upgrades need no special handling. Cost: about 512 MiB RAM and one more volume. Switch when the per-node interruption or the manual steps during Talos/Kubernetes upgrades start to bother you.

Rules: the IdP never protects its own recovery path; every service in the break-glass list keeps a local admin with its own MFA where the product supports it, documented with its 1Password item; restore is rehearsed in `rebuild`.

Resource estimate for `prod`: Keycloak 2 × ~1 GiB, PostgreSQL ~512 MiB, Longhorn volume 5 GiB with 2–3 replicas. Small compared with the worker sizing.

## Integration levels

Every service moves toward one of three levels; each level is useful on its own:

1. **Central identity:** users and passwords come from UCS (LDAP/AD bind or via the IdP); no personal local accounts, only break-glass.
2. **Central MFA:** the second factor is enrolled once in Keycloak, not per service (today `sebi-adm` uses a Proxmox-local TOTP on top of the AD realm).
3. **SSO:** an existing Keycloak session logs the user in without asking again.

Levels 2 and 3 require the service to authenticate through Keycloak (OIDC, SAML, or a proxy in front of it). A direct LDAP/AD bind stays at level 1: the password alone opens it, so such a service keeps its own local second factor where it has one.

## Service matrix

"Verified" means checked against vendor documentation in this pass; "Phase 0" means the deployed version or edition must still be confirmed.

| Service | Mechanism | Realm | Local break-glass | Notes |
| --- | --- | --- | --- | --- |
| Kubernetes API ([#1766](https://github.com/isejalabs/homelab/issues/1766)) | Native OIDC (structured authn config) + kubelogin | admin (and iseja for read-only, optional) | `talosctl kubeconfig` | Verify Talos machine-config support for structured authn |
| Flux Operator UI ([#1726](https://github.com/isejalabs/homelab/issues/1726)) | Native OIDC, Kubernetes impersonation | admin | `kubectl` via break-glass kubeconfig | Verified that Flux Operator documents a Keycloak SSO guide; requires ≥ 0.40.0 (impersonation bypass with empty claims fixed, GO-2026-4351) |
| Longhorn ([#1725](https://github.com/isejalabs/homelab/issues/1725)) | oauth2-proxy + `CiliumNetworkPolicy` | admin | `kubectl port-forward` to `longhorn-frontend` | Monitoring keeps its own Basic Auth path ([#1714](https://github.com/isejalabs/homelab/issues/1714)) |
| Zigbee2MQTT ([#1767](https://github.com/isejalabs/homelab/issues/1767)) | oauth2-proxy | iseja (group `app-z2m-users`) | port-forward | After [#1682](https://github.com/isejalabs/homelab/issues/1682) |
| Immich ([#1768](https://github.com/isejalabs/homelab/issues/1768)) | Native OIDC, mobile redirect | iseja | Immich local admin | After [#413](https://github.com/isejalabs/homelab/issues/413); needs a trusted certificate |
| actualbudget (new) | Native OpenID | iseja | Server password | Phase 0: confirm deployed version supports it |
| AdGuard (new) | oauth2-proxy, or keep local | admin | Local user | Low priority |
| Proxmox ([#1728](https://github.com/isejalabs/homelab/issues/1728)) | Native OIDC realm, groups claim + autocreate | admin | `root@pam` | Keep the AD realm until OIDC proves out; Phase 0: PVE version |
| RustFS ([#1729](https://github.com/isejalabs/homelab/issues/1729)) | Native OIDC (console; groups claim → policy names) | admin | RustFS root user | Verified in RustFS docs; S3 keys unaffected |
| Checkmk ([#1727](https://github.com/isejalabs/homelab/issues/1727)) | SAML if commercial edition; otherwise LDAP to UCS or HTTP-header auth behind oauth2-proxy | admin | `cmkadmin` | Verified: SAML is commercial-only; Phase 0: edition |
| OPNsense ([#1730](https://github.com/isejalabs/homelab/issues/1730)) | No OIDC/SAML login → target level 1: LDAP to UCS, plus a local second factor if OPNsense can combine one with LDAP | — | `root` | Phase 0: which OPNsense auth-server types combine with TOTP |
| TrueNAS ([#1731](https://github.com/isejalabs/homelab/issues/1731)) | No OIDC/SAML login → level 1 already in place (AD); add TrueNAS's own 2FA for directory admins if supported | — | `truenas_admin` | Phase 0: whether TrueNAS 2FA applies to directory users |
| UniFi controller (new) | Local only | — | Local admin | Document only |
| Home Assistant (new) | Investigate: community/HACS OIDC integration or header-auth proxy; meanwhile local with HA's MFA | iseja | Owner account | Weigh a third-party auth component against the gain |
| UCS portal/UMC (new) | Its own SAML IdP; out of scope | — | `Administrator` | Linked to D9 |

## Phases

### Phase 0 — Live inventory

- UCS version and patch level; which IdP serves `ucs-sso.dir.iseja.net` (Univention Keycloak app vs. SimpleSAMLphp); every Keycloak/PostgreSQL component from the PoC on both DCs; what depends on it (portal, UMC, any SAML client).
- Kerberos: realm, KDCs, how Windows and Mac clients obtain tickets, whether an `HTTP/` SPN can be added for a non-`dir.iseja.net` hostname.
- Account model: existing groups, `sebi` / `sebi-adm` membership, family accounts.
- Deployed versions/editions: Proxmox, Checkmk edition, RustFS, OPNsense, TrueNAS, actualbudget, Flux Operator.

Acceptance: a written inventory in #1715; D9 resolved; D11 rows confirmed.

### Phase 1 — IdP platform (`qa` first, then `prod`, then `rebuild`)

- CloudNativePG operator and Keycloak Operator as infra units under `k8s/infra/`; Keycloak 2 replicas; database backups to RustFS.
- Terragrunt unit for realm content: `iseja` and `admin` realms, LDAP federation (both DCs, read-only, import + periodic sync, group mapper), flows, password policy, brute-force protection.
- Restore drill in `rebuild`: restore the database from backup and log in with an existing passkey.

Acceptance: login with `sebi` (iseja) and `sebi-adm` (admin) in the same browser simultaneously; `adelheid` stopped → logins still work; database stopped on purpose → behaviour recorded against the expectations in [Availability and recovery](#what-still-works-while-the-database-is-unavailable); a node drain of the PostgreSQL node completes; restore drill documented.

### Phase 2 — Kerberos and MFA proof

- SPN and keytab; Kerberos on the `iseja` realm; client policies for Windows and macOS.
- MFA flows per D4/D5; WebAuthn enrollment (passkey, YubiKey) for `sebi-adm`; TOTP fallback; step-up level for sensitive `iseja` apps.
- Kerberos exposure per D5: KDC ports restricted to trusted VLANs on OPNsense; inventory of SSH (key-only on UCS, TrueNAS, Linux hosts) and RDP access.

Acceptance: a domain-joined Mac and a Windows client open a `iseja` client without a prompt; a phone gets password + second factor; the `admin` realm never accepts Kerberos; a step-up client asks for a second factor after Kerberos; `kinit` from an untrusted VLAN fails.

### Phase 3 — First integrations (closes the open Longhorn exposure)

Flux Operator UI (native), Longhorn (oauth2-proxy + network policy), Kubernetes API ([#1766](https://github.com/isejalabs/homelab/issues/1766)).

### Phase 4 — Remaining integrations

Immich, actualbudget, RustFS, Proxmox, Checkmk, Zigbee2MQTT, AdGuard; record OPNsense/TrueNAS/UniFi/Home Assistant as local-auth-retained.

### Phase 5 — Clean-up and options

Remove proven-unused Keycloak PoC parts from UCS; optionally consolidate oauth2-proxy instances onto Gateway `ExternalAuth` once Cilium ≥ 1.20 runs in `prod`; re-evaluate Nubus when it can co-exist with or replace UCS network services.

## Nubus path

Nubus for Kubernetes ships Keycloak (with a Univention authenticator SPI), OpenLDAP and UDM; UCS remains required for AD-compatible domain services, DHCP and DNS. Choosing upstream Keycloak now keeps the protocols, client registrations and realm design transferable. The migration trigger is "Nubus can take over the directory role from UCS without losing Samba AD / DNS / DHCP", not a date. Until then a Nubus deployment would be a second directory to keep in sync, which this design avoids.

## Issue changes (made 2026-10-21)

- New sub-issues of [#1715](https://github.com/isejalabs/homelab/issues/1715): IdP platform [#1826](https://github.com/isejalabs/homelab/issues/1826); Kerberos browser SSO and MFA policy [#1827](https://github.com/isejalabs/homelab/issues/1827); UCS Keycloak PoC removal and portal login [#1828](https://github.com/isejalabs/homelab/issues/1828); Actual Budget [#1829](https://github.com/isejalabs/homelab/issues/1829); AdGuard [#1830](https://github.com/isejalabs/homelab/issues/1830); Home Assistant [#1831](https://github.com/isejalabs/homelab/issues/1831); optional Cilium `ExternalAuth` consolidation [#1832](https://github.com/isejalabs/homelab/issues/1832), moved out of #1715's acceptance.
- [#1826](https://github.com/isejalabs/homelab/issues/1826) blocks every integration that needs Keycloak: [#1766](https://github.com/isejalabs/homelab/issues/1766), [#1725](https://github.com/isejalabs/homelab/issues/1725), [#1726](https://github.com/isejalabs/homelab/issues/1726), [#1767](https://github.com/isejalabs/homelab/issues/1767), [#1768](https://github.com/isejalabs/homelab/issues/1768), [#1727](https://github.com/isejalabs/homelab/issues/1727), [#1728](https://github.com/isejalabs/homelab/issues/1728), [#1729](https://github.com/isejalabs/homelab/issues/1729), [#1827](https://github.com/isejalabs/homelab/issues/1827), [#1829](https://github.com/isejalabs/homelab/issues/1829), [#1830](https://github.com/isejalabs/homelab/issues/1830), [#1831](https://github.com/isejalabs/homelab/issues/1831). OPNsense ([#1730](https://github.com/isejalabs/homelab/issues/1730)) and TrueNAS ([#1731](https://github.com/isejalabs/homelab/issues/1731)) are not blocked: their target is central identity via LDAP/AD.
- The UCS stability issues ([#1813](https://github.com/isejalabs/homelab/issues/1813), [#1816](https://github.com/isejalabs/homelab/issues/1816), [#1821](https://github.com/isejalabs/homelab/issues/1821)) are related to, not blocking, the platform issue.
- ADR 0016 had been merged as an unfinished planning draft; with the owner's agreement it is rewritten in place with the accepted decisions (a one-off exception to the no-rewrite rule for merged ADRs), so the diff shows this pass's changes.

## Sources

- [Keycloak Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/index.html) — LDAP failover with space-separated connection URLs, Kerberos, conditional flows, LoA (`acr`)
- [authentik Kerberos source](https://docs.goauthentik.io/users-sources/sources/protocols/kerberos/) — SPNEGO support
- [Flux Web UI SSO with Keycloak](https://fluxoperator.dev/docs/web-ui/sso-keycloak/) and [GO-2026-4351](https://osv.dev/vulnerability/GO-2026-4351)
- [RustFS OIDC](https://docs.rustfs.com/administration/iam/oidc)
- [Checkmk SAML](https://docs.checkmk.com/latest/en/saml.html) — commercial editions only
- [Proxmox OIDC group sync patch](https://lore.proxmox.com/all/20240215212739.602-1-alexis@danwalex.com/t) and [Pocket ID's Proxmox example](https://pocket-id.org/docs/client-examples/proxmox) (groups claim, autocreate)
- [CloudNativePG: Kubernetes upgrade and maintenance](https://github.com/cloudnative-pg/cloudnative-pg/blob/main/docs/src/kubernetes_upgrade.md) — single-instance clusters block node drains unless `enablePDB: false`
- [Univention Keycloak app: federation](https://docs.software-univention.de/keycloak-app/latest/ad-hoc-provisioning.html), [database](https://docs.software-univention.de/keycloak-app/latest/database.html)
- [Nubus for Kubernetes 1.0 release](https://www.univention.com/blog-en/2024/11/nubus-for-kubernetes-1-0-productive-version-released/)
