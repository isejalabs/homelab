---
status: current
---

# Checkmk human SSO

Browser sign-in to the Checkmk sites through the identity provider of [ADR 0016](../decisions/0016-identity-and-web-sso.md). Tracking: [#1727](https://github.com/isejalabs/homelab/issues/1727); the design is in [the plan comment](https://github.com/isejalabs/homelab/issues/1727#issuecomment-6557954802). Only the Ultimate sites `dev_k8s` and `qa_k8s` ([#2107](https://github.com/isejalabs/homelab/issues/2107)) are covered so far; `prod_k8s` ([#2108](https://github.com/isejalabs/homelab/issues/2108)) and the Community site `prod` ([#2109](https://github.com/isejalabs/homelab/issues/2109)) are added when they are built. The sites and their editions are in [`monitoring-sites.md`](../reference/monitoring-sites.md).

**Status (2026-11-02):** the UCS groups exist, and for `dev_k8s` and `qa_k8s` the Keycloak clients are applied and both SAML connections are created in the site. The login page shows the two buttons and Keycloak accepts the request of each. Complete logins were verified by the owner for `sebi`, `sebi-adm` and `mary` in `dev_k8s` and `qa_k8s`; the users the sites created are `sebi` (role `user`, contact group `all`, in `qa_k8s` with the e-mail address), `sebi-adm` (role `admin`, no contact group) and `mary` (role `guest`). The page describes these two sites; `prod_k8s` and `prod` are not set up and are added when they are.

## How it works

The Ultimate sites speak SAML. Keycloak is the identity provider and Checkmk is the service provider, one SAML connection per realm, because a connection trusts a single identity provider. `iseja` carries everyday accounts and `admin` the `*-adm` accounts with WebAuthn. Checkmk creates the user at the first login and updates alias and roles at every login. It refuses a SAML login whose user ID matches a local user, so the local users (`cmkadmin`, `terraform`, `automation`, `agent_registration`) are never taken over.

| Part | Where it lives |
| --- | --- |
| SAML clients and mappers in Keycloak | Code: the `saml_clients` input of the unit [`dev/keycloak-realm`](../../terragrunt/non-prod/eu-central-1/dev/keycloak-realm/terragrunt.hcl) (and `qa`), module [`keycloak-realm`](https://github.com/isejalabs/terraform-modules/tree/main/modules/keycloak-realm) |
| UCS groups `sec.app.checkmk.*` | `udm` on a domain controller, see [below](#ucs-groups) |
| SAML connections in Checkmk | By hand in the site, see [below](#checkmk-side). The provider of [ADR 0015](../decisions/0015-checkmk-configuration-as-code.md) has no SAML resource |

## Access model

Realm membership (`sec.idm.users`, `sec.idm.admins`) only admits an account to a realm; a role in Checkmk needs a `sec.app.checkmk.*` group.

| Account | Realm | UCS group | Checkmk role |
| --- | --- | --- | --- |
| `sebi-adm` | `admin` | `sec.app.checkmk.admin` | `admin` |
| `sebi` | `iseja` | `sec.app.checkmk.operator` | `user`, plus contact group `all` |
| `mary` | `iseja` | `sec.app.checkmk.readonly` | `guest` |

- The built-in role `user` can acknowledge and run commands but only sees hosts of its contact groups, so `sebi` is mapped into the contact group `all`, which exists on `dev_k8s` and `qa_k8s`. `sebi-adm` stays out of `all`. No custom role is created.
- The mail rule notifies all contacts of an object, so membership of `all` plus an e-mail address makes a user a recipient. The e-mail attribute is therefore only sent where notifications are on: the `iseja` client of `qa_k8s` (`include_email`), not `dev_k8s`. See [`monitoring-notifications.md`](../reference/monitoring-notifications.md).
- `mary` is in `sec.idm.users` (added 2026-11-02, see [Changing who has access](#changing-who-has-access)): membership of that group grants access to the `iseja` realm, so adding an account there is a decision of its own.

## UCS groups

Done once for the domain, as `root` on a domain controller, like the realm groups in [`keycloak-realms.md`](keycloak-realms.md#ucs-setup); the naming scheme is in [`ucs-groups.md`](ucs-groups.md). The groups can be empty; the `(cn=sec.app.*)` filter of the realms imports them at the next sync.

```sh
BASE="dc=dir,dc=iseja,dc=net"

udm groups/group create --position "cn=groups,$BASE" --set name=sec.app.checkmk.admin    --set description="Checkmk role admin (admin realm accounts)"
udm groups/group create --position "cn=groups,$BASE" --set name=sec.app.checkmk.operator --set description="Checkmk role user plus contact group all (iseja realm accounts)"
udm groups/group create --position "cn=groups,$BASE" --set name=sec.app.checkmk.readonly --set description="Checkmk role guest (iseja realm accounts)"

udm groups/group modify --dn "cn=sec.app.checkmk.admin,cn=groups,$BASE"    --append users="uid=sebi-adm,cn=users,$BASE"
udm groups/group modify --dn "cn=sec.app.checkmk.operator,cn=groups,$BASE" --append users="uid=sebi,cn=users,$BASE"
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

Per site, once for `iseja` and once for `admin`, in *Setup → Users → SAML authentication → Add connection* or through the REST API (`POST /domain-types/saml_connection/collections/all`, available in 2.5.0p15). Checkmk requires HTTPS, and the user ID attribute must be the full attribute name. The REST API was used on 2026-11-01 and 2026-11-02 from `monitoring1` against the site's own Apache port (`http://127.0.0.1:<port>/<site>/check_mk/api/1.0`, `dev_k8s` 5083, `qa_k8s` 5082): `dev_k8s` as its `automation` user with the secret read from the site, `qa_k8s` (which has no automation user) as `cmkadmin` with the password from 1Password, neither ever printed. The connections are saved at once, they are not a pending change to activate.

| Field | `iseja` connection | `admin` connection |
| --- | --- | --- |
| Connection ID | `keycloak_iseja` | `keycloak_admin` |
| Name (login button label) | `Iseja` | `Admin` |
| Identity provider metadata (URL) | `.../realms/iseja/protocol/saml/descriptor` | `.../realms/admin/protocol/saml/descriptor` |
| Checkmk server URL | `https://monitoring1.home.iseja.net`, the host only without the site name (Checkmk adds `/<site>/check_mk`) | same |
| Signing certificate | built-in | built-in |
| User ID attribute | `https://iseja.net/claims/userid` | same |
| Full name attribute | `https://iseja.net/claims/alias` | same |
| E-mail attribute | `https://iseja.net/claims/email` on `qa_k8s` only | not set |
| Roles | attribute `https://iseja.net/claims/groups`: `sec.app.checkmk.operator` → `user`, `sec.app.checkmk.readonly` → `guest` | `sec.app.checkmk.admin` → `admin` |
| Contact groups | type "map" on the same attribute: `sec.app.checkmk.operator` → `all` | none |

The connections were accepted with the Ultimate sites in the free licence state, so the licence does not block SAML configuration. The REST body mirrors the table: `general_properties` (`id`, `name`), `connection_config` (`checkmk_server_url`, `identity_provider_metadata` of type `url`), `security` (`signing_certificate` of type `builtin`) and `users` (`id_attribute`, `full_name_attribute`, `email_attribute`, `contact_groups` and `roles` of type `map`). After the first login of each connection, Checkmk's request-signing certificate can be added to the Keycloak client as `signing_certificate`, which makes Keycloak require signed requests; this is not done yet.

## First login and activation

A user that Checkmk creates at its first SAML login is a **pending change** in the site (one per user). Until an administrator activates it with *Activate changes*, the user exists but the monitoring configuration does not know them: the contact group membership (`all` for `sebi`) is not in effect and the user sees no hosts or services. Seen on 2026-11-02 in `dev_k8s`: `sebi` logged in first and saw nothing; after `sebi-adm` had logged in, two changes (the two new users) were pending, and activating them made the views fill.

- **Every new SAML user needs this once**, not every login. Changes of the mapping applied by later logins (a role or contact group that changed in UCS) are pending changes again.
- **Who activates:** a user with the `admin` role, for instance `sebi-adm` through the `admin` connection, or the local `cmkadmin`.
- **Do not activate blindly:** activation applies all pending changes of the site, not only the new users (see the consequences in ADR 0015), so look at the list first.
- **Not automated.** Activating after a first login is a manual step on purpose for now; whether it should be scripted is a follow-up if it becomes a nuisance.

## Changing who has access

A UCS group change takes three steps to reach a Checkmk login, and the middle one is **not immediate**:

1. **UCS:** add or remove the account in the `sec.app.checkmk.*` group (and in `sec.idm.users` or `sec.idm.admins` for the realm), see [UCS groups](#ucs-groups). Both domain controllers show it at once (`memberOf`).
2. **Keycloak:** the federation reads the group membership of an imported user only when it syncs that user. The changed-users sync runs every **3600 s** (`ldap.changed_sync_period`) and the full sync every 86400 s, so a change takes up to an hour to arrive. The interval stays at one hour on purpose (owner decision, 2026-11-02); a shorter `changed_sync_period` in [`keycloak-realm.hcl`](../../terragrunt/_envcommon/keycloak-realm.hcl) would apply to every environment. To skip the wait, trigger it in the admin console of the realm under *User federation → ucs → Sync changed users* (or `POST .../user-storage/<id>/sync?action=triggerChangedUsersSync`).
3. **Checkmk:** roles and contact groups are applied at each login, so the next login after step 2 is enough. A newly created user still needs the [activation](#first-login-and-activation).

Seen on 2026-11-02 in `dev_k8s`: `mary` was added to `sec.idm.users` and `sec.app.checkmk.readonly` and her login failed, while Keycloak still held her as an imported user without groups; one changed-users sync later `sec.app.checkmk.readonly` appeared in Keycloak and her logins worked in `dev_k8s` and `qa_k8s`.

**A user without any `sec.app.checkmk.*` group cannot log in.** Keycloak then sends no groups attribute at all, and Checkmk refuses the login with `Configured user attribute cannot be found in response` in `var/log/web.log` of the site (logger `cmk.web.saml2`, owner-tested on `dev_k8s`, 2026-11-02). The same message appears for a user whose group change has not reached Keycloak yet, so that log line alone does not say which of the two it is: look at the user's *Groups* in the Keycloak admin console.

## Kerberos

Kerberos SPNEGO (silent sign-in from a workstation ticket) is not part of this setup. It belongs to the `iseja` realm of Keycloak and comes with [#1827](https://github.com/isejalabs/homelab/issues/1827); until then every login, including `sebi`'s, asks for the Keycloak password. Checkmk itself needs no change for it, because it only trusts the SAML assertion.

## Regression check: agent registration

A change to how users log in must not break agents registering at a site. Registration goes to the site's own **agent receiver port**, not to 443 (`omd config show AGENT_RECEIVER_PORT` as the site user: `dev_k8s` 8083, `qa_k8s` 8082 on `monitoring1`, `prod` 8001 on `monitoring2`), authenticated as the htpasswd user `agent_registration` with its automation secret. SAML and LDAP connections do not touch that path, and the check proves it without registering a host:

```sh
CMK_REGISTRATION_PASSWORD=<secret of agent_registration> \
  scripts/checkmk-agent-registration-check.sh --server monitoring1.home.iseja.net --port 8083 --site dev_k8s
```

[`checkmk-agent-registration-check.sh`](../../scripts/checkmk-agent-registration-check.sh) sends the registration request of the Agent Controller for a host name that does not exist. A wrong password must be refused with 401, and the right secret must end with 404 `Host ... does not exist`, which is the answer of the REST API call made as `agent_registration`, so the receiver reached the site and accepted the user. The secret is read from the environment, not from a flag, and the receiver certificate is not verified (it is signed by the site's own CA), so the check covers authentication, not trust.

- **Result (2026-11-02):** passes on `dev_k8s` and `qa_k8s` with both SAML connections in place, and fails with exit 1 for a wrong secret. No run before the connections existed, so there is no baseline from before the change; the code paths do not overlap.
- **`pairing` is not part of it:** `POST /pairing` answers 403 `You do not have the permission for agent pairing` for `agent_registration` on both sites. In 2.5.0p15 only the `admin` role has `general.agent_pairing` by default and the sites have no role overrides, so this is the default, not a result of SAML.
- **Not covered:** the registration of a real host (it changes the host's UUID and trust) and the pull/TLS connection after it.

## Break-glass

`cmkadmin` is the local administrator of every `*_k8s` site (password in 1Password) and works without Keycloak, UCS or Kubernetes, because the login form stays next to the SAML buttons. The automation users are unaffected. Verified on `dev_k8s` on 2026-11-02 with the `dev` Keycloak stopped (its Flux `Kustomization` suspended and `spec.instances` of the `Keycloak` resource set to 0, restored after about five minutes): the metadata URL answered 503, the login page still loaded with the local form, `cmkadmin` logged in with it and reached the Checkmk index, and the REST API accepted `cmkadmin`. The same check was not repeated on `qa_k8s`.

## Not verified yet

- Registering a real host end to end (only the non-destructive [regression check](#regression-check-agent-registration) was run).
