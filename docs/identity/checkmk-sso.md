---
status: planning
---

# Checkmk human SSO

Browser sign-in to the Checkmk sites through the identity provider of [ADR 0016](../decisions/0016-identity-and-web-sso.md). Tracking: [#1727](https://github.com/isejalabs/homelab/issues/1727); the design is in [the plan comment](https://github.com/isejalabs/homelab/issues/1727#issuecomment-6557954802). Only the Ultimate sites `dev_k8s` and `qa_k8s` ([#2107](https://github.com/isejalabs/homelab/issues/2107)) are covered so far; `prod_k8s` ([#2108](https://github.com/isejalabs/homelab/issues/2108)) and the Community site `prod` ([#2109](https://github.com/isejalabs/homelab/issues/2109)) are added when they are built. The sites and their editions are in [`monitoring-sites.md`](../reference/monitoring-sites.md).

**Status:** the Keycloak side of `dev_k8s` is applied; the Checkmk side and the logins are **not** configured or verified yet, and neither is anything for `qa_k8s`. This page is `planning` until the acceptance criteria of #2107 are checked.

## How it works

The Ultimate sites speak SAML. Keycloak is the identity provider and Checkmk is the service provider, one SAML connection per realm, because a connection trusts a single identity provider. `iseja` carries everyday accounts and `admin` the `*-adm` accounts with WebAuthn. Checkmk creates the user at the first login and updates alias and roles at every login. It refuses a SAML login whose user ID matches a local user, so the local users (`cmkadmin`, `terraform`, `automation`, `agent_registration`) are never taken over.

| Part | Where it lives |
| --- | --- |
| SAML clients and mappers in Keycloak | Code: the `saml_clients` input of the unit [`dev/keycloak-realm`](../../terragrunt/non-prod/eu-central-1/dev/keycloak-realm/terragrunt.hcl) (and `qa`), module [`keycloak-realm`](https://github.com/isejalabs/terraform-modules/tree/main/modules/keycloak-realm) |
| UCS groups `app-checkmk-*` | `udm` on a domain controller, see [below](#ucs-groups) |
| SAML connections in Checkmk | By hand in the site, see [below](#checkmk-side). The provider of [ADR 0015](../decisions/0015-checkmk-configuration-as-code.md) has no SAML resource |

## Access model

Realm membership (`idm-users`, `idm-admins`) only admits an account to a realm; a role in Checkmk needs an `app-checkmk-*` group.

| Account | Realm | UCS group | Checkmk role |
| --- | --- | --- | --- |
| `sebi-adm` | `admin` | `app-checkmk-admin` | `admin` |
| `sebi` | `iseja` | `app-checkmk-operator` | `user`, plus contact group `all` |
| `mary` | `iseja` | `app-checkmk-readonly` | `guest` |

- The built-in role `user` can acknowledge and run commands but only sees hosts of its contact groups, so `sebi` is mapped into the contact group `all`, which exists on `dev_k8s` and `qa_k8s`. `sebi-adm` stays out of `all`. No custom role is created.
- The mail rule notifies all contacts of an object, so membership of `all` plus an e-mail address makes a user a recipient. The e-mail attribute is therefore only sent where notifications are on: the `iseja` client of `qa_k8s` (`include_email`), not `dev_k8s`. See [`monitoring-notifications.md`](../reference/monitoring-notifications.md).
- `mary` has a UCS account but is not in `idm-users` yet. Adding her grants a second person access to the `iseja` realm, so it is a separate decision.

## UCS groups

Done once for the domain, as `root` on a domain controller, like the realm groups in [`keycloak-realms.md`](keycloak-realms.md#ucs-setup). The groups can be empty; the `(cn=app-*)` filter of the realms imports them at the next sync.

```sh
BASE="dc=dir,dc=iseja,dc=net"

udm groups/group create --position "cn=groups,$BASE" --set name=app-checkmk-admin    --set description="Checkmk role admin (admin realm accounts)"
udm groups/group create --position "cn=groups,$BASE" --set name=app-checkmk-operator --set description="Checkmk role user plus contact group all (iseja realm accounts)"
udm groups/group create --position "cn=groups,$BASE" --set name=app-checkmk-readonly --set description="Checkmk role guest (iseja realm accounts)"

udm groups/group modify --dn "cn=app-checkmk-admin,cn=groups,$BASE"    --append users="uid=sebi-adm,cn=users,$BASE"
udm groups/group modify --dn "cn=app-checkmk-operator,cn=groups,$BASE" --append users="uid=sebi,cn=users,$BASE"
```

## Keycloak side

The unit creates, per site, one client in `iseja` and one in `admin`, with the entity ID `https://monitoring1.home.iseja.net/<site>/check_mk/saml_metadata.py` and the assertion consumer URL `.../saml_acs.py?acs`. Keycloak signs assertion and document with RSA-SHA256 and sends these attributes, with names in URI format as Checkmk requires:

| Attribute | Content |
| --- | --- |
| `https://iseja.net/claims/userid` | the username |
| `https://iseja.net/claims/alias` | the username |
| `https://iseja.net/claims/groups` | the names of the user's `app-*` groups, multi-valued |
| `https://iseja.net/claims/email` | the e-mail address, only for clients with `include_email` |

The identity provider metadata URLs are an output of the unit (`terragrunt output saml_idp_metadata_urls`), for `dev`: `https://dev-auth.dev.iseja.net/realms/iseja/protocol/saml/descriptor` and `.../realms/admin/protocol/saml/descriptor`. `monitoring1` reaches them and trusts their certificate (checked 2026-11-01), so the metadata can be entered as a URL.

## Checkmk side

Per site, in *Setup → Users → SAML authentication → Add connection*, once for `iseja` and once for `admin`. Checkmk requires HTTPS, and the user ID attribute must be the full attribute name.

| Field | `iseja` connection | `admin` connection |
| --- | --- | --- |
| Connection ID | `keycloak_iseja` | `keycloak_admin` |
| Name (login button label) | `Iseja` | `Admin` |
| Identity provider metadata (URL) | `.../realms/iseja/protocol/saml/descriptor` | `.../realms/admin/protocol/saml/descriptor` |
| Checkmk server URL | `https://monitoring1.home.iseja.net`, the host only without the site name (Checkmk adds `/<site>/check_mk`) | same |
| User ID attribute | `https://iseja.net/claims/userid` | same |
| Alias attribute | `https://iseja.net/claims/alias` | same |
| E-mail attribute | `https://iseja.net/claims/email` on `qa_k8s` only | not set |
| Roles | by attribute `https://iseja.net/claims/groups`: `app-checkmk-operator` → `user`, `app-checkmk-readonly` → `guest` | `app-checkmk-admin` → `admin` |
| Contact groups | by the same attribute: `app-checkmk-operator` → `all` | none |

The exact form of the role and contact group mapping has not been tried; the Checkmk source offers a direct attribute-to-group mapping and a group mapping by attribute value, and which one reproduces the table is part of the first spike. After the first login of each connection, Checkmk's request-signing certificate can be added to the Keycloak client as `signing_certificate`, which makes Keycloak require signed requests; this is not done yet.

## Break-glass

`cmkadmin` is the local administrator of every `*_k8s` site (password in 1Password) and works without Keycloak, UCS or Kubernetes, because the login form stays next to the SAML buttons. The automation users are unaffected. Test it with the identity provider stopped before the site is called done; not exercised yet.

## Not verified yet

- SAML works in the free licence state of the Ultimate sites (no licence check was found in the source; not run).
- A user in no mapped group gets no role or access.
- The contact group mapping puts `app-checkmk-operator` members into `all`.
- The assertion is accepted: signature algorithm and attribute names.
- `cmkadmin` and the automation users keep working with a SAML connection configured and with the identity provider stopped.
