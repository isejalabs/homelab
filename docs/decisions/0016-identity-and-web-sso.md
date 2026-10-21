# Identity and web SSO architecture

## Status

planning — accepted by the owner on 2026-10-21; becomes `current` once the platform ([#1826](https://github.com/isejalabs/homelab/issues/1826)) runs in `prod`.

This ADR was first merged as an unfinished planning draft ([#1724](https://github.com/isejalabs/homelab/pull/1724)) and rewritten in place with the accepted design ([#1833](https://github.com/isejalabs/homelab/pull/1833)). That is a one-off exception to the rule that a merged ADR body is not rewritten: the first version was never meant to be settled. The diff of #1833 shows what changed.

## Context

The first planning version of this ADR set the boundaries for human web SSO (UCS stays authoritative, native OIDC preferred, MFA, break-glass, machine credentials separate) but deferred the identity provider, its placement and its availability design, and made a Cilium 1.20 `ExternalAuth` proof the central browser pattern. An independent second design pass, [`docs/plans/2026-10-identity-claude.md`](../plans/2026-10-identity-claude.md), reviewed those points against the requirements in [#1715](https://github.com/isejalabs/homelab/issues/1715): OIDC for apps such as Immich, browser SSO from the macOS/Windows Kerberos login, 2FA, separate everyday and admin accounts (`sebi`, `sebi-adm`), configuration as code instead of changes on the UCS hosts, quick recovery rather than HA, and a later path to Nubus. The plan's "Differences from the first pass" table (D1–D13) and the owner's review of it hold the full reasoning; this ADR records the result.

## Options considered

- **IdP product.** The hard requirements (OIDC, SAML, LDAP/AD federation, Kerberos SPNEGO, conditional MFA) leave Keycloak and authentik; Authelia, Zitadel, Kanidm and Pocket ID lack SPNEGO. Keycloak is also the IdP inside Nubus.
- **Keycloak on the UCS servers** (Univention Keycloak app). Same software, but configured by hand, on DCs with 2.5 GB RAM ([#1816](https://github.com/isejalabs/homelab/issues/1816)), next to the unstable `adelheid` ([#1813](https://github.com/isejalabs/homelab/issues/1813)), and still needing an external PostgreSQL for shared state.
- **Keycloak in Kubernetes**, deployed by Flux, database by CloudNativePG, realm content by OpenTofu.
- **Browser apps without native SSO:** Gateway API `ExternalAuth` (needs Cilium ≥ 1.20 and experimental CRDs in `prod`) or oauth2-proxy as a reverse proxy per app (works on the current Cilium).

## Decision

1. **Keycloak in Kubernetes** is the identity provider. Keycloak on UCS is not used as the IdP; the unused proof of concept there is removed ([#1828](https://github.com/isejalabs/homelab/issues/1828)).
2. **Placement:** `prod` hosts the authoritative instance, which also serves out-of-cluster services (Proxmox, RustFS, Checkmk). `qa` runs its own instance as the upgrade and configuration gate; `rebuild` runs one to rehearse restore. The other non-prod environments register their UIs in the `prod` instance.
3. **UCS stays authoritative** for users, passwords and groups. Keycloak federates it read-only over LDAPS, both DCs listed for failover, users imported and synced. Authorization is granted through UCS groups mapped into a `groups` claim.
4. **Two realms:** an everyday realm (working name `home`; the final name is fixed before the first client is registered in [#1826](https://github.com/isejalabs/homelab/issues/1826), because a realm name becomes part of every issuer URL) for everyday accounts (Kerberos SPNEGO allowed) and `admin` for `*-adm` accounts only (UCS password plus WebAuthn — passkey or YubiKey — with TOTP as fallback, never Kerberos). Admin UIs trust only `admin`, everyday apps only `home`; both sessions can coexist in one browser.
5. **MFA:** in the everyday realm, a Kerberos ticket is accepted as sufficient and every password login needs a second factor; sensitive apps request a step-up level. Because a Kerberos ticket can be obtained with the password alone from anywhere that reaches a KDC, KDC ports are restricted to trusted VLANs and password-based remote access (SSH, RDP) is inventoried and reduced ([#1827](https://github.com/isejalabs/homelab/issues/1827)).
6. **Recovery over HA:** 2 Keycloak replicas; CloudNativePG with 1 instance (`enablePDB: false`), scaling to 2 when node drains become a nuisance; database backups to RustFS; realm configuration in Git. Targets: restore within 1 h, at most 24 h of MFA enrollments lost.
7. **Configuration as code:** Keycloak server via the Keycloak Operator (Flux); realm content via the `keycloak/keycloak` OpenTofu provider in Terragrunt units.
8. **Integration per service:** native OIDC where available (Kubernetes API, Flux Operator UI, Immich, Actual Budget, RustFS, Proxmox); oauth2-proxy plus a `CiliumNetworkPolicy` for browser UIs without their own login (Longhorn, Zigbee2MQTT, AdGuard). Services that can only bind LDAP/AD (OPNsense, TrueNAS) stay at "central identity" with their own second factor. Gateway `ExternalAuth` is not a prerequisite; it is evaluated later as an optional consolidation ([#1832](https://github.com/isejalabs/homelab/issues/1832)).
9. **Break-glass:** every core service keeps a local login that depends on neither the IdP, Kubernetes nor UCS (Proxmox `root@pam`, OPNsense `root`, TrueNAS admin, RustFS root user, Checkmk `cmkadmin`, Talos-issued admin kubeconfig).

Unchanged from the first planning version: machine and monitoring credentials stay independent of human SSO ([#1714](https://github.com/isejalabs/homelab/issues/1714)); Kubernetes API access uses OIDC with least-privilege RBAC ([#1766](https://github.com/isejalabs/homelab/issues/1766)); a Longhorn replica count is not database HA.

## Consequences

- Every SSO login depends on the `prod` cluster and at least one UCS DC; when either is down, administration falls back to the break-glass logins, which therefore have to be documented and tested per service.
- Non-prod environments depend on `prod` for SSO; `prod` never depends on a non-prod environment.
- A single PostgreSQL instance means a short window without new logins whenever its node is drained (Talos/Kubernetes upgrades); existing application sessions continue.
- A lost database without a usable backup loses MFA enrollments, forcing every user to re-enroll.
- Nubus remains a later option: its IdP is Keycloak, so protocols, client registrations and the realm design carry over; the migration trigger is Nubus taking over the directory role from UCS without losing AD, DNS and DHCP.
- Work is tracked as sub-issues of [#1715](https://github.com/isejalabs/homelab/issues/1715), starting with the platform [#1826](https://github.com/isejalabs/homelab/issues/1826), which blocks the integrations.
