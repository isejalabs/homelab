# Keycloak realms

The realm content of the identity provider ([ADR 0016](decisions/0016-identity-and-web-sso.md), point 7) is managed by the Terragrunt unit `keycloak-realm` per environment, which uses the module [`keycloak-realm`](https://github.com/isejalabs/terraform-modules/tree/main/modules/keycloak-realm) from `isejalabs/terraform-modules`. The Keycloak server itself is deployed by Flux (`k8s/apps/identity/keycloak`); this unit only fills it.

The unit creates the realms `iseja` (everyday accounts) and `admin` (`*-adm` accounts), each with a **read-only** LDAP federation to UCS and a `groups` client scope. Kerberos, the MFA flows and the OIDC clients come with [#1827](https://github.com/isejalabs/homelab/issues/1827) and the per-service integrations.

The directory facts (base DN, domain controllers, bind account, group names) and the realm definitions are stated once in [`terragrunt/_envcommon/keycloak-realm.hcl`](../terragrunt/_envcommon/keycloak-realm.hcl); only the Keycloak URL differs per environment.

## Prerequisites

Apply the unit **from `main`** (`qa`, `prod`), after the Keycloak instance of the environment is up and answers on its URL.

1. **Admin login:** the 1Password item `keycloak-bootstrap-admin#<env>` (the same item the Keycloak Operator uses) with `username` and `password`. The provider logs in with it through the `admin-cli` client.
2. **UCS bind account:** a read-only account on UCS that may search users and groups, and its 1Password item `keycloak-ldap-bind#<env>` with the password in the `password` field. Create it by hand on UCS; nothing in this repo manages UCS.
3. **Network:** the Keycloak pods must reach both domain controllers on LDAPS (636) and trust the certificate of the UCS CA. Keycloak creates the federation without connecting, so a gap only shows at the first sync.
4. **Reachability from your machine:** the Keycloak URL of the environment must be reachable from where you run Terragrunt (the internal Gateway).

## Apply and verify

```sh
source terragrunt/non-prod/eu-central-1/qa/.envrc
cd terragrunt/non-prod/eu-central-1/qa/keycloak-realm
terragrunt plan
terragrunt apply
```

Then, in the Keycloak admin console of each realm, open *User federation* → `ucs` → *Test connection* and *Test authentication*, run *Synchronize all users*, and check that only the accounts of that realm's filter arrive and that their groups appear under *Groups*.

## Caveats

- A user filter decides which realm an account may use. Keep the `iseja` and `admin` filters disjoint.
- Changing a realm name destroys the realm and everything in it, and changes every issuer URL.
- The bind credential and the admin login are part of the Terraform state; the state bucket is access-controlled per environment.
