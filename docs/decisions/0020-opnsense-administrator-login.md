---
id: ADR 0020
status: current
accepted: 2026-11-11
---

# OPNsense administrator login through OIDC

## Context

[ADR 0016](0016-identity-and-web-sso.md) sets human web sign-in to go through Keycloak with UCS authoritative, and in point 8 leaves the services that can only bind LDAP or AD, OPNsense among them, at "central identity" with their own second factor. That point rested on one finding of the first investigation ([#2237](https://github.com/isejalabs/homelab/issues/2237)): the Community Edition of OPNsense has no OIDC login. The finding was incomplete. Core has no OIDC login of its own, but it has a provider hook that third-party plugins use, and two community plugins implement OIDC for the web interface. A proof of concept ([#2238](https://github.com/isejalabs/homelab/issues/2238), details in [`opnsense-auth.md`](../identity/opnsense-auth.md#oidc-with-os-sso-proof-of-concept-on-gw3)) showed one of them working on the backup gateway.

Facts that bound the choice:

- The firewall pair is outside this repository and configured by hand. It routes for the cluster (BGP peer) and for UCS (gateway and DHCP relay of its VLAN), while the administrators' identity lives in UCS and Keycloak on the cluster. Whatever is chosen must leave a login that depends on neither.
- OPNsense's own TOTP asks for the token in front of the password in one field, and keeps the seed in each local user. That is the main reason the LDAP route is cumbersome.
- Both gateways run the same release (26.7.6_3, read from the boxes). The HA sync on the master has users, authentication servers, aliases, rules and similar items ticked; the web-interface settings (including the login list), certificates and plugin settings are not among them.

## Options considered

- **Local accounts only (status quo).** Works and is simple, but is not central identity and repeats the second-factor seed per account and per box.
- **LDAP against UCS with local TOTP (`ldap-totp`).** Core only, no third-party code. The token typed in front of the password makes it awkward with a password manager, the seed lives in every local user, a bind account has to exist and its password sits in the firewall configuration. Documented in full as the fallback.
- **OIDC through the Business Edition.** The official feature, but it needs the Business Edition; not used.
- **A RADIUS or LDAP bridge in front of Keycloak.** Extra components and a second factor that still has to fit a password field; not pursued.
- **OIDC through the `opnsense-openid-connect` plugin.** Web interface only, a beta release when looked at, not installed.
- **OIDC through the `os-sso` plugin.** Chosen. Third-party code from a single maintainer, but it is small, BSD-licensed, kept in the ordinary authentication-server list, and its release package was identical to the tagged source (85 of 85 files, vendored libraries identical to upstream). It refuses to bind a login to an account with a real local password or to an administrator account it did not create itself.

## Decision

1. **Administrators sign in to the OPNsense web interface through OIDC with the Keycloak realm `admin`**, using the `os-sso` plugin, restricted to the web interface. Keycloak owns the second factor ([`keycloak-mfa.md`](../identity/keycloak-mfa.md)); the plugin sends `max_age` so that an existing Keycloak session does not replace it.
2. **`root` stays a local account with the local second factor** as the break-glass login, with the existing login list untouched. Console and SSH are not changed.
3. **One local account per administrator on each gateway, created with the plugin's own account writer** (no usable password), bound to the Keycloak subject at the first login. Nothing is created automatically from the directory. Access is gated by the UCS group `sec.app.opnsense.admin` through the plugin's required groups.
4. **The plugin is third-party code that is vetted, not trusted.** Each install or update is a pinned release compared with its tagged source first; updates are manual.
5. **LDAP with local TOTP stays documented** as the alternative should the plugin be dropped.
6. This **refines point 8 of ADR 0016** for OPNsense; it does not supersede that ADR.

Production steps and their order are tracked in [#2238](https://github.com/isejalabs/homelab/issues/2238).

## Consequences

- The firewall administrator login now depends on production Keycloak (cluster, database, UCS federation). `root` with its local second factor breaks the loop, which is why it is not touched. Measured on 2026-11-11 with Keycloak unreachable from one gateway: the button fails after about 8 seconds and `root` works. A new `sec.app.*` group needs a manual group sync in Keycloak before its first use.
- The plugin is installed per gateway (a package is not synced), and its settings and its ownership marker for accounts are not part of the HA sync. Accounts are therefore created on each gateway, with the same numeric user id so that a user list synced from the master keeps matching the marker on the other box. Observed on 2026-11-11: the account created on the master reached the backup through the daily sync and worked there, because the marker already existed from the proof of concept; for a new account the marker has to be created on each box. A leftover binding to a differently named provider blocks a login under strict binding until it is cleared.
- The HA sync copies the list of authentication servers from the master to the backup, so an entry added by hand on the backup is replaced by the master's list at its next sync. The production server entry is configured on the master.
- Single-maintainer risk and a manual update burden are accepted; the fallback above is the exit.
- In the firewall's audit log the configuration write at the login callback is attributed to `root` and the client address, not to the signed-in user, so "who changed this" has to be read around SSO logins with care.
- Evidence written into issues, PRs and documentation follows [ADR 0019](0019-public-disclosure-policy.md): placeholder account names, no personal details.
