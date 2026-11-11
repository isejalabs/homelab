---
status: current
---

# Checkmk human SSO

Browser sign-in to the Checkmk sites through the identity provider of [ADR 0016](../decisions/0016-identity-and-web-sso.md). Tracking: [#1727](https://github.com/isejalabs/homelab/issues/1727); the design is in [the plan comment](https://github.com/isejalabs/homelab/issues/1727#issuecomment-6557954802). The Ultimate sites `dev_k8s` and `qa_k8s` ([#2107](https://github.com/isejalabs/homelab/issues/2107)) are covered, and `prod_k8s` ([#2108](https://github.com/isejalabs/homelab/issues/2108)) is wired to the **prod** identity provider, see [below](#prod_k8s-prod-identity-provider). The Community site `prod` ([#2109](https://github.com/isejalabs/homelab/issues/2109)) has no SAML: it takes users and roles from UCS over LDAP, see [below](#prod-community-ldap), and signs humans in with OpenID Connect in the system Apache of `monitoring2`, see [below](#prod-community-openid-connect-through-the-system-apache). The sites and their editions are in [`monitoring-sites.md`](../reference/monitoring-sites.md).

**Status (2026-11-02):** the UCS groups exist, and for `dev_k8s` and `qa_k8s` the Keycloak clients are applied and both SAML connections are created in the site. The login page shows the two buttons and Keycloak accepts the request of each. Complete logins were verified by the owner for `bob`, `bob-adm` and `alice` in `dev_k8s` and `qa_k8s`; the users the sites created are `bob` (role `user`, contact group `all`, in `qa_k8s` with the e-mail address), `bob-adm` (role `admin`, no contact group) and `alice` (role `guest`). The page describes these two sites; `prod` is not set up and is added when it is.

**Status of `prod_k8s` (2026-11-08):** both SAML connections point at the **prod** Keycloak (`auth.iseja.net`). The owner verified `bob` (role `user`, contact group `all`), `bob-adm` (role `admin`), `alice` (role `guest`), the refusal of a user without a `sec.app.checkmk.*` group, and the local `cmkadmin` form login, first against the qa Keycloak (stage 1 of [#2108](https://github.com/isejalabs/homelab/issues/2108)) and again after the switch to the prod one (stage 2).

## How it works

The Ultimate sites speak SAML. Keycloak is the identity provider and Checkmk is the service provider, one SAML connection per realm, because a connection trusts a single identity provider. `iseja` carries everyday accounts and `admin` the `*-adm` accounts with WebAuthn. Checkmk creates the user at the first login and updates alias and roles at every login. It refuses a SAML login whose user ID matches a local user, so the local users (`cmkadmin`, `terraform`, `automation`, `agent_registration`) are never taken over.

| Part | Where it lives |
| --- | --- |
| SAML clients and mappers in Keycloak | Code: the `saml_clients` input of the unit [`dev/keycloak-realm`](../../terragrunt/non-prod/eu-central-1/dev/keycloak-realm/terragrunt.hcl) (and `qa`, and [`prod`](../../terragrunt/prod/eu-central-1/prod/keycloak-realm/terragrunt.hcl) for `prod_k8s`), module [`keycloak-realm`](https://github.com/isejalabs/terraform-modules/tree/main/modules/keycloak-realm) |
| UCS groups `sec.app.checkmk.*` | `udm` on a domain controller, see [below](#ucs-groups) |
| SAML connections in Checkmk | By hand in the site, see [below](#checkmk-side). The provider of [ADR 0015](../decisions/0015-checkmk-configuration-as-code.md) has no SAML resource |

## Access model

Realm membership (`sec.idm.users`, `sec.idm.admins`) only admits an account to a realm; a role in Checkmk needs a `sec.app.checkmk.*` group.

| Account | Realm | UCS group | Checkmk role |
| --- | --- | --- | --- |
| `bob-adm` | `admin` | `sec.app.checkmk.admin` | `admin` |
| `bob` | `iseja` | `sec.app.checkmk.operator` | `user`, plus contact group `all` |
| `alice` | `iseja` | `sec.app.checkmk.readonly` | `guest` |

- The built-in role `user` can acknowledge and run commands but only sees hosts of its contact groups, so `bob` is mapped into the contact group `all`, which exists on `dev_k8s`, `qa_k8s` and `prod_k8s`. `bob-adm` stays out of `all`. No custom role is created.
- The mail rule notifies all contacts of an object, so membership of `all` plus an e-mail address makes a user a recipient. The e-mail attribute is therefore only sent where notifications are on: the `iseja` client of `qa_k8s` (`include_email`), not `dev_k8s` and not `prod_k8s` (notifications there are not enabled yet, [#1901](https://github.com/isejalabs/homelab/issues/1901)). See [`monitoring-notifications.md`](../reference/monitoring-notifications.md).
- `alice` is in `sec.idm.users` (added 2026-11-02, see [Changing who has access](#changing-who-has-access)): membership of that group grants access to the `iseja` realm, so adding an account there is a decision of its own.

## UCS groups

Done once for the domain, as `root` on a domain controller, like the realm groups in [`keycloak-realms.md`](keycloak-realms.md#ucs-setup); the naming scheme is in [`ucs-groups.md`](ucs-groups.md). The groups can be empty; the `(cn=sec.app.*)` filter of the realms imports them at the next sync.

```sh
BASE="dc=dir,dc=iseja,dc=net"

udm groups/group create --position "cn=groups,$BASE" --set name=sec.app.checkmk.admin    --set description="Checkmk role admin (admin realm accounts)"
udm groups/group create --position "cn=groups,$BASE" --set name=sec.app.checkmk.operator --set description="Checkmk role user plus contact group all (iseja realm accounts)"
udm groups/group create --position "cn=groups,$BASE" --set name=sec.app.checkmk.readonly --set description="Checkmk role guest (iseja realm accounts)"

udm groups/group modify --dn "cn=sec.app.checkmk.admin,cn=groups,$BASE"    --append users="uid=bob-adm,cn=users,$BASE"
udm groups/group modify --dn "cn=sec.app.checkmk.operator,cn=groups,$BASE" --append users="uid=bob,cn=users,$BASE"
```

## Keycloak side

The unit creates, per site, one client in `iseja` and one in `admin`, with the entity ID `https://monitoring1.home.iseja.net/<site>/check_mk/saml_metadata.py` and the assertion consumer URL `.../saml_acs.py?acs`. Keycloak signs assertion and document with RSA-SHA256 and sends these attributes, with names in URI format as Checkmk requires:

| Attribute | Content |
| --- | --- |
| `https://iseja.net/claims/userid` | the username |
| `https://iseja.net/claims/alias` | the username |
| `https://iseja.net/claims/groups` | the names of the user's `sec.app.*` groups, multi-valued |
| `https://iseja.net/claims/email` | the e-mail address, only for clients with `include_email` |

The `https://iseja.net/claims/` prefix is only a namespace that makes the attribute names unique, like an XML namespace: nothing is ever fetched from it, it need not resolve, and it is the same in every environment (it is not replaced by `dev-auth.dev.iseja.net` or any other host). It has to be a URL because Checkmk insists on a user ID attribute name that starts with `http`. It is the default of `saml_claims` in the module and can be overridden there, but the Keycloak mappers and the Checkmk connection must use the same names.

The identity provider metadata URLs are an output of the unit (`terragrunt output saml_idp_metadata_urls`), for `dev`: `https://dev-auth.dev.iseja.net/realms/iseja/protocol/saml/descriptor` and `.../realms/admin/protocol/saml/descriptor`. `monitoring1` reaches them and trusts their certificate (checked 2026-11-01), so the metadata can be entered as a URL.

## Checkmk side

Per site, once for `iseja` and once for `admin`, in *Setup → Users → SAML authentication → Add connection* or through the REST API (`POST /domain-types/saml_connection/collections/all`, available in 2.5.0p15). Checkmk requires HTTPS, and the user ID attribute must be the full attribute name. The REST API was used on 2026-11-01 and 2026-11-02 from `monitoring1` against the site's own Apache port (`http://127.0.0.1:<port>/<site>/check_mk/api/1.0`, `dev_k8s` 5083, `qa_k8s` 5082): `dev_k8s` as its `automation` user with the secret read from the site, `qa_k8s` (which has no automation user) as `cmkadmin` with the password from 1Password, neither ever printed. On 2026-11-08 `prod_k8s` (port 5088 on `monitoring2`) got its connections the same way as its `terraform` automation user, with the secret read from the site into a shell variable; the site's audit log therefore shows `terraform` as the author. The connections are saved at once, they are not a pending change to activate.

| Field | `iseja` connection | `admin` connection |
| --- | --- | --- |
| Connection ID | `keycloak_iseja` | `keycloak_admin` |
| Name (login button label) | `Iseja` | `Admin` |
| Identity provider metadata (URL) | `.../realms/iseja/protocol/saml/descriptor` | `.../realms/admin/protocol/saml/descriptor` |
| Checkmk server URL | `https://monitoring1.home.iseja.net` (`monitoring2` for `prod_k8s`), the host only without the site name (Checkmk adds `/<site>/check_mk`) | same |
| Signing certificate | built-in | built-in |
| User ID attribute | `https://iseja.net/claims/userid` | same |
| Full name attribute | `https://iseja.net/claims/alias` | same |
| E-mail attribute | `https://iseja.net/claims/email` on `qa_k8s` only (not `prod_k8s`) | not set |
| Roles | attribute `https://iseja.net/claims/groups`: `sec.app.checkmk.operator` → `user`, `sec.app.checkmk.readonly` → `guest` | `sec.app.checkmk.admin` → `admin` |
| Contact groups | type "map" on the same attribute: `sec.app.checkmk.operator` → `all` | none |

**Changing a connection later:** the REST API of 2.5.0p15 creates, reads and deletes a SAML connection but does not update one: the response lists an update (`PUT`) link, yet `PUT` answers 405 (tried on `prod_k8s`, 2026-11-08). Deleting the connection risks the users it created. Edit it in *Setup → Users → SAML authentication*, or, as done for the group rename of 2026-11-01, change `etc/check_mk/multisite.d/wato/user_connections.mk` as the site user (keep a backup copy, check that the file still parses, then read the connection back with the REST `GET`). See [`ucs-groups.md`](ucs-groups.md#migration-of-the-first-names).

The connections were accepted with the Ultimate sites in the free licence state, so the licence does not block SAML configuration. The REST body mirrors the table: `general_properties` (`id`, `name`), `connection_config` (`checkmk_server_url`, `identity_provider_metadata` of type `url`), `security` (`signing_certificate` of type `builtin`) and `users` (`id_attribute`, `full_name_attribute`, `email_attribute`, `contact_groups` and `roles` of type `map`). After the first login of each connection, Checkmk's request-signing certificate can be added to the Keycloak client as `signing_certificate`, which makes Keycloak require signed requests; this is not done yet.

## `prod_k8s`: prod identity provider

The Ultimate site `prod_k8s` (on `monitoring2`, 2.5.0p15, Apache port 5088, agent receiver port 8088) was set up in two stages on 2026-11-08 ([#2108](https://github.com/isejalabs/homelab/issues/2108)). Stage 1 connected it to the **qa** Keycloak as a rehearsal, because the Keycloak of `prod` was not applied yet. Stage 2 switched it to the **prod** Keycloak.

- **Keycloak:** the clients `prod_k8s-iseja` and `prod_k8s-admin` are in the `saml_clients` of the **prod** unit ([`prod/keycloak-realm`](../../terragrunt/prod/eu-central-1/prod/keycloak-realm/terragrunt.hcl)). Entity ID `https://monitoring2.home.iseja.net/prod_k8s/check_mk/saml_metadata.py`, no e-mail attribute. The temporary clients in the qa unit were removed again after the switch.
- **Checkmk:** `keycloak_iseja` and `keycloak_admin` as in the [table above](#checkmk-side), with the metadata URLs `https://auth.iseja.net/realms/<realm>/protocol/saml/descriptor`, server URL `https://monitoring2.home.iseja.net`, and the same mapping as `qa_k8s` (without e-mail). Before creating them, `monitoring2` was checked to reach the URLs and the site's Python to trust the certificate.
- **Accounts:** the realms of qa and prod are federated to the same UCS, so the same accounts and groups apply. The users the site created are `bob` (`user`, contact group `all`), `bob-adm` (`admin`, no contact group) and `alice` (`guest`). They stay the same across the switch as long as the user IDs (usernames) are the same in both identity providers.
- **Switch method:** the connections were created through the REST API as the `terraform` user. For the switch the REST `PUT` answered 405, so `etc/check_mk/multisite.d/wato/user_connections.mk` was edited as the site user: backup `user_connections.mk.bak-2108-stage2` kept next to it, the two metadata URLs and the connection comments changed, the file parse-checked and written atomically, the result read back with the REST `GET`. To roll back, copy the backup file over `user_connections.mk`.
- **Login tests (owner, 2026-11-08), against qa and again against prod:** `bob` through *Iseja*, `bob-adm` through *Admin*, `alice` through *Iseja*, a user without a `sec.app.checkmk.*` group refused, `cmkadmin` through the local form. All passed.

## `prod` (Community): LDAP

The site `prod` on `monitoring2` is Community 2.5.0p15, which has no SAML and no native OpenID Connect login ([plan, track B](https://github.com/isejalabs/homelab/issues/1727#issuecomment-6557954802)). Its users and roles come from UCS over LDAP; the login by OpenID Connect through the web server is the [next section](#prod-community-openid-connect-through-the-system-apache). Until that is switched on, a human logs in at the form with the UCS password, without a second factor.

Done on 2026-11-08 ([#2109](https://github.com/isejalabs/homelab/issues/2109), phase 2), with the findings of the spikes in [that issue](https://github.com/isejalabs/homelab/issues/2109):

| Part | Setting |
| --- | --- |
| Bind account | UCS user `checkmk-ro` (ordinary user in `Domain Users`, no `sec.*` group), created with `udm users/user create` like `keycloak-ro` in [`keycloak-realms.md`](keycloak-realms.md#ucs-setup). Password in 1Password, `monitoring2/prod#checkmk-ro` (vault `IT Infrastructure`); in the site it is the password-store entry `checkmk_ro_ucs` |
| Connection `ucs` | Type OpenLDAP, server `baerbel.dir.iseja.net`, failover `adelheid.dir.iseja.net`, LDAPS port 7636, certificate verified against the trusted CAs, sync every 5 minutes, users created at sync (not at login, because the header route never checks a password) |
| Users | Base `cn=users,dc=dir,dc=iseja,dc=net`, filter `(&(objectClass=person)(\|(memberOf=<sec.app.checkmk.admin>)(memberOf=<sec.app.checkmk.operator>)(memberOf=<sec.app.checkmk.readonly>)))` with the full group DNs, user ID `uid`, alias from `displayName`, no e-mail (notifications are not enabled on `prod`) |
| Groups | Base `cn=groups,dc=dir,dc=iseja,dc=net`, filter `(objectClass=univentionGroup)`, member attribute `uniqueMember` |
| Roles | `sec.app.checkmk.admin` → `admin`, `sec.app.checkmk.operator` → `user`, `sec.app.checkmk.readonly` → `guest` (group DNs, a bare CN is rejected) |
| Contact group | `sec.app.checkmk.operator` → the contact group of the **same name**, see below |
| Trusted CA | The UCS CA (`CN=iseja.net Directory Services`, valid until 2027-12-29) added to the trusted CAs of the site |

- **The contact group is `sec.app.checkmk.operator`, not `all`.** The LDAP plug-in adds a user only to a contact group whose name equals the LDAP group's CN, and the "groups to custom user attributes" plug-in cannot set contact groups. So the group `sec.app.checkmk.operator` exists in the site, and a second unconditional host rule next to the existing "Put all hosts into the contact group `all`" assigns every host to it (the values add up; all 93 hosts show `sec.app.checkmk.operator,check-mk-notify,all`). `bob` is a member, `bob-adm` and `alice` are in no contact group, as in the [access model](#access-model). The local users that stay (`omdadmin`, `terraform`, `automation`, `automation-cmk-agent-ctl`) keep `all`.
- **Local `bob` and `alice` were deleted** before the first sync, because a local user and an LDAP user with the same ID clash; the sync recreated them as LDAP users (`bob` role `user`, `bob-adm` role `admin`, `alice` role `guest`). Their profile directories held only default files.
- **The CA needs an activation.** Adding it to the trusted CAs is only effective after *Activate changes* regenerates `var/ssl/ca-certificates.crt`; before that the sync fails with `certificate verify failed`. The activation applies every pending change, so the list was read first (empty, then only the contact group and the rule). Users created by the sync are a pending change too, activated once so that `bob` is a contact of the core, see [First login and activation](#first-login-and-activation).
- **How it was configured:** through the REST API of the site as its `automation` user (secret read from the site into a shell variable, never printed; the audit log shows `automation`): `contact_group_config`, `rule` (ruleset `host_contactgroups`), `password` and `ldap_connection`, the connection created deactivated and enabled after the local users were gone. Community has the `ldap_connection` endpoint (`POST`, `GET`, `PUT`, `DELETE`); the SAML one is Ultimate only.
- **Rollback:** disable or delete the connection `ucs`, delete the three users it created, remove the rule and the contact group, and restore the local users from `/root/backup-2109-pre-ldap.tgz` on `monitoring2` (config of `conf.d/wato`, `multisite.d` and the two profile directories as of before the change; `root`-only).
- **A user without a `sec.app.checkmk.*` group is not imported**, so there is no account to log in with.

## `prod` (Community): OpenID Connect through the system Apache

**Status (2026-11-10): live on `prod`.** The Keycloak clients are defined in [`prod/keycloak-realm`](../../terragrunt/prod/eu-central-1/prod/keycloak-realm/terragrunt.hcl) (applied from `main`, 6 resources added), the Apache configuration is the Salt state `apps.check-mk.server.oidc` ([`sebiklamar/salt-iseja.net`](https://github.com/sebiklamar/salt-iseja.net/pull/41), applied by the owner), and the site setting is on. Results: [Rollout and results](#rollout-and-results-of-the-openid-connect-login).

Community has no SAML and no OIDC login, so the web server in front of the site does the OIDC part and passes the user name on. The system Apache of `monitoring2` is the only listener on 443; the site's own Apache listens on 127.0.0.1 only. That makes the system Apache the trust boundary for the header `X-Remote-User`, which Checkmk accepts once the site setting `auth_by_http_header = "X-Remote-User"` is on. Why this and not oauth2-proxy: the amendment of 2026-11-09 in [ADR 0016](../decisions/0016-identity-and-web-sso.md#amendments).

| Entry point | Keycloak realm | Client | Admitted groups |
| --- | --- | --- | --- |
| `monitoring2.home.iseja.net` | `iseja` | `checkmk-prod-iseja` | `sec.app.checkmk.operator`, `sec.app.checkmk.readonly` |
| `monitoring.home.iseja.net` | `admin` (WebAuthn) | `checkmk-prod-admin` | `sec.app.checkmk.admin` |

- **Flow.** The browser asks `/prod`; `mod_auth_openidc` sends it to Keycloak (authorization code with PKCE S256, scopes `openid profile groups`), checks the `groups` claim with `Require claim`, and sets `X-Remote-User` from `preferred_username` (the UCS user ID, which is also the LDAP user ID in Checkmk). The Checkmk role and contact group come from the LDAP sync, [above](#prod-community-ldap).
- **The client secrets** are generated by the Keycloak module and written to the 1Password items `keycloak-oidc-checkmk-prod-{iseja,admin}#prod` (vault `K8S`); Salt reads them through the `onepassword` ext_pillar into root-only files on `monitoring2`. The cookie passphrase of the module is generated once on the host.
- **Strip first.** Every request loses any `X-Remote-User` (and its underscore spellings, which a WSGI server would map to the same name). The site accepts the header from anyone who reaches it, so an Apache without this config in front of a site with the setting on would let anybody log in as any user: apply the Salt state before the site setting.
- **An unknown name is not refused by Checkmk.** In 2.5.0p15 a header with a name that no user has creates a session with role `user` and no contact group (sees nothing). The refusal happens in Apache by the group claim; a UCS user who is in a group but was not synced yet gets exactly that empty session until the next sync (5 minutes). The name is case-sensitive.
- **Password and header cannot mix.** Checkmk ranks a Basic or Bearer login above the header, and a human's UCS password works on the REST API with no second factor. So `Authorization` is removed on every OIDC-protected request, and the login form is blocked on the public names (`POST` to `login.py` and `_username`/`_password` in its query answer 403). The REST API keeps its own login only for the automation users `terraform`, `automation` and `automation-cmk-agent-ctl` (the Terraform provider uses Basic auth); a human uses the browser session.
- **Logout** is rewritten to the OIDC logout, otherwise the next request would log the user straight in again. The Checkmk session cookie itself stays valid until its own idle timeout, so a stolen cookie outlives the OIDC session for that time; the OIDC session lasts 8 hours at most and 1 hour idle.
- **Distributed monitoring, agent registration and Livestatus** do not go through 443 (the agent receiver is port 8001, Livestatus TLS 6601) and are unaffected; the `prod_k8s` and `free` sites on the same Apache are not configured by this.

**Test bed (owner, 2026-11-09):** a second Apache on port 8443 with the same configuration in front of a throwaway Checkmk 2.5.0p15 site (LDAP connection as on `prod`, header setting on), against the dev Keycloak. Passed: `bob` and `alice` through the `iseja` entry point, `bob-adm` through the `admin` entry point with WebAuthn, a UCS user without a `sec.app.checkmk.*` group refused by Apache (403), `bob` refused on the `admin` entry point, the logout ending the Keycloak session without logging in again, and the login form not accepting a password. A first run failed because `%{REMOTE_USER}e` sends the text `(null)` as the header value; the `expr=%{REMOTE_USER}` form is the right one. The test bed, the throwaway site and the temporary dev clients were removed afterwards.

### Rollout and results of the OpenID Connect login

Done on 2026-11-10 ([#2109](https://github.com/isejalabs/homelab/issues/2109), phase 3), in this order, because the site trusts the header from anyone who reaches it:

1. **Keycloak clients** applied from `main` ([PR 2253](https://github.com/isejalabs/homelab/pull/2253)): plan 6 to add, 0 to change, 0 to destroy (two clients, their default scopes, the 1Password items `keycloak-oidc-checkmk-prod-{iseja,admin}#prod`).
2. **Salt state** `apps.check-mk.server.oidc` applied on `monitoring2` after the two `onepassword_items` entries were added to its pillar and a copy of `/etc/apache2` was taken (`/root/backup-2109-pre-oidc.tgz`). Checked afterwards: `apache2ctl configtest` OK; both host names redirect to their Keycloak realm and client; a forged `X-Remote-User` through 443 is redirected to Keycloak instead of accepted; a `POST` to `login.py` answers 403; a human's password on the REST API goes to Keycloak; `prod_k8s` on the same Apache is unchanged (200).
3. **Site setting** `auth_by_http_header = "X-Remote-User"` added to `etc/check_mk/multisite.d/wato/global.mk` of `prod` right after (previous file: `/root/global.mk.pre-2109-header` on `monitoring2`). It is effective without a restart: a request straight to the site with the header is accepted, without it the site shows its login page.

| Test | Result |
| --- | --- |
| `bob` at `monitoring2.home.iseja.net`: Keycloak login with second factor, straight into Checkmk as `user` | passed (owner) |
| `alice` at the same address: `guest` | passed (owner) |
| `bob-adm` at `monitoring.home.iseja.net` with WebAuthn: `admin` | passed (owner) |
| `bob` at the admin address; a user without a `sec.app.checkmk.*` group at either address | refused by Apache, passed (owner) |
| Logout in Checkmk ends the Keycloak session | passed (owner) |
| Break-glass: SSH tunnel to `127.0.0.1:5001`, local `omdadmin` | passed (owner) |
| REST API as `terraform` through the public name | `GET /version` 200 with Bearer and with Basic (the Terraform provider uses Basic); the 403 on the contact group list is the same when asking the site directly, so it comes from the strict role of ADR 0015, not from Apache |
| Agent registration, [regression check](#regression-check-agent-registration) against port 8001 | passed: wrong secret 401, right secret 404 for the unknown host. `prod` has no `agent_registration` user, so the check ran as `automation-cmk-agent-ctl` (`--user`), through an SSH tunnel |

**Rollback:** delete the `auth_by_http_header` line from `global.mk` (the login form still does not accept a password on the public names while the Apache config is in place), then restore the previous Apache files from the backup if the whole OIDC front is to go; Salt does not delete the files it wrote.

**Break-glass for `prod`:** the local `omdadmin` on the site's own Apache, reached through an SSH tunnel (`ssh -L 5001:127.0.0.1:5001 root@monitoring2.home.iseja.net`, then `http://127.0.0.1:5001/prod/`). That Apache has no OIDC configuration, so the login form works there. With the header setting on, anyone with a shell on `monitoring2` can also send the header to port 5001 themselves, which is why the host stays root-only.

**Not covered:** distributed monitoring between the sites uses Livestatus TLS (6601) and the agent receiver (8001), which do not pass through the Apache; both ports still listen, but a connection test between the sites was not run. Registering a real host was not run either. A Checkmk crash report on 2026-11-10 shows a stored dashboard with the widget type `average_scatterplot`, which Community does not know; it is a dashboard configuration problem and independent of the login.

## First login and activation

A user that Checkmk creates at its first SAML login is a **pending change** in the site (one per user). Until an administrator activates it with *Activate changes*, the user exists but the monitoring configuration does not know them: the contact group membership (`all` for `bob`) is not in effect and the user sees no hosts or services. Seen on 2026-11-02 in `dev_k8s`: `bob` logged in first and saw nothing; after `bob-adm` had logged in, two changes (the two new users) were pending, and activating them made the views fill.

- **Every new SAML user needs this once**, not every login. Changes of the mapping applied by later logins (a role or contact group that changed in UCS) are pending changes again.
- **Who activates:** a user with the `admin` role, for instance `bob-adm` through the `admin` connection, or the local `cmkadmin`.
- **Do not activate blindly:** activation applies all pending changes of the site, not only the new users (see the consequences in ADR 0015), so look at the list first.
- **Not automated.** Activating after a first login is a manual step on purpose for now; whether it should be scripted is a follow-up if it becomes a nuisance.

## Changing who has access

A UCS group change takes three steps to reach a Checkmk login, and the middle one is **not immediate**:

1. **UCS:** add or remove the account in the `sec.app.checkmk.*` group (and in `sec.idm.users` or `sec.idm.admins` for the realm), see [UCS groups](#ucs-groups). Both domain controllers show it at once (`memberOf`).
2. **Keycloak:** the federation reads the group membership of an imported user only when it syncs that user. The changed-users sync runs every **3600 s** (`ldap.changed_sync_period`) and the full sync every 86400 s, so a change takes up to an hour to arrive. The interval stays at one hour on purpose (owner decision, 2026-11-02); a shorter `changed_sync_period` in [`keycloak-realm.hcl`](../../terragrunt/_envcommon/keycloak-realm.hcl) would apply to every environment. To skip the wait, trigger it in the admin console of the realm under *User federation → ucs → Sync changed users* (or `POST .../user-storage/<id>/sync?action=triggerChangedUsersSync`).
3. **Checkmk:** roles and contact groups are applied at each login, so the next login after step 2 is enough. A newly created user still needs the [activation](#first-login-and-activation).

Seen on 2026-11-02 in `dev_k8s`: `alice` was added to `sec.idm.users` and `sec.app.checkmk.readonly` and her login failed, while Keycloak still held her as an imported user without groups; one changed-users sync later `sec.app.checkmk.readonly` appeared in Keycloak and her logins worked in `dev_k8s` and `qa_k8s`.

**A user without any `sec.app.checkmk.*` group cannot log in.** Keycloak then sends no groups attribute at all, and Checkmk refuses the login with `Configured user attribute cannot be found in response` in `var/log/web.log` of the site (logger `cmk.web.saml2`, owner-tested on `dev_k8s`, 2026-11-02). The same message appears for a user whose group change has not reached Keycloak yet, so that log line alone does not say which of the two it is: look at the user's *Groups* in the Keycloak admin console.

## Kerberos

Kerberos SPNEGO (silent sign-in from a workstation ticket) is not part of this setup. It belongs to the `iseja` realm of Keycloak and comes with [#1827](https://github.com/isejalabs/homelab/issues/1827); until then every login, including `bob`'s, asks for the Keycloak password. Checkmk itself needs no change for it, because it only trusts the SAML assertion.

## Regression check: agent registration

A change to how users log in must not break agents registering at a site. Registration goes to the site's own **agent receiver port**, not to 443 (`omd config show AGENT_RECEIVER_PORT` as the site user: `dev_k8s` 8083, `qa_k8s` 8082 on `monitoring1`, `prod` 8001 and `prod_k8s` 8088 on `monitoring2`), authenticated as the htpasswd user `agent_registration` with its automation secret. SAML and LDAP connections do not touch that path, and the check proves it without registering a host:

```sh
CMK_REGISTRATION_PASSWORD=<secret of agent_registration> \
  scripts/tools/checkmk-agent-registration-check.sh --server monitoring1.home.iseja.net --port 8083 --site dev_k8s
```

[`checkmk-agent-registration-check.sh`](../../scripts/tools/checkmk-agent-registration-check.sh) sends the registration request of the Agent Controller for a host name that does not exist. A wrong password must be refused with 401, and the right secret must end with 404 `Host ... does not exist`, which is the answer of the REST API call made as `agent_registration`, so the receiver reached the site and accepted the user. The secret is read from the environment, not from a flag, and the receiver certificate is not verified (it is signed by the site's own CA), so the check covers authentication, not trust.

- **Result (2026-11-02):** passes on `dev_k8s` and `qa_k8s` with both SAML connections in place, and fails with exit 1 for a wrong secret. No run before the connections existed, so there is no baseline from before the change; the code paths do not overlap.
- **Result for `prod_k8s` (2026-11-08):** passes with both connections in place (401 for a wrong secret, 404 for the right one). Port 8088 is not reachable from the workstation, so the script ran against `127.0.0.1` through an SSH tunnel (`ssh -L 18088:127.0.0.1:8088 root@monitoring2.home.iseja.net`).
- **Result for `prod` (2026-11-10):** passes with the OpenID Connect front and the header setting in place (401 for a wrong secret, 404 for the right one) on port 8001, as `automation-cmk-agent-ctl`, through an SSH tunnel.
- **`pairing` is not part of it:** `POST /pairing` answers 403 `You do not have the permission for agent pairing` for `agent_registration` on both sites. In 2.5.0p15 only the `admin` role has `general.agent_pairing` by default and the sites have no role overrides, so this is the default, not a result of SAML.
- **Not covered:** the registration of a real host (it changes the host's UUID and trust) and the pull/TLS connection after it.

## Break-glass

`cmkadmin` is the local administrator of every `*_k8s` site (password in 1Password) and works without Keycloak, UCS or Kubernetes, because the login form stays next to the SAML buttons. The automation users are unaffected. Verified on `dev_k8s` on 2026-11-02 with the `dev` Keycloak stopped (its Flux `Kustomization` suspended and `spec.instances` of the `Keycloak` resource set to 0, restored after about five minutes): the metadata URL answered 503, the login page still loaded with the local form, `cmkadmin` logged in with it and reached the Checkmk index, and the REST API accepted `cmkadmin`. The same check was not repeated on `qa_k8s`. On `prod_k8s` the local form login of `cmkadmin` was verified by the owner on 2026-11-08 with the identity provider reachable, and again during the Keycloak failover test of [#1956](https://github.com/isejalabs/homelab/issues/1956) with both domain controllers blocked on the network (Keycloak could not reach its directory); it worked. In that test Keycloak itself was not stopped, so the case of an unreachable Keycloak is covered by the `dev_k8s` check above, not by a run on `prod_k8s`.

## Not verified yet

- Registering a real host end to end (only the non-destructive [regression check](#regression-check-agent-registration) was run).
