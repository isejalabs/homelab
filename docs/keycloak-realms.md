# Keycloak realms

The realm content of the identity provider ([ADR 0016](decisions/0016-identity-and-web-sso.md), point 7) is managed by the Terragrunt unit `keycloak-realm` per environment, which uses the module [`keycloak-realm`](https://github.com/isejalabs/terraform-modules/tree/main/modules/keycloak-realm) from `isejalabs/terraform-modules`. The Keycloak server itself is deployed by Flux (`k8s/apps/identity/keycloak`); this unit only fills it.

The unit creates the realms `iseja` (everyday accounts) and `admin` (`*-adm` accounts), each with a **read-only** LDAP federation to UCS and a `groups` client scope. Kerberos, the MFA flows and the OIDC clients come with [#1827](https://github.com/isejalabs/homelab/issues/1827) and the per-service integrations.

The directory facts (base DN, domain controllers, bind account, group names) and the realm definitions are stated once in [`terragrunt/_envcommon/keycloak-realm.hcl`](../terragrunt/_envcommon/keycloak-realm.hcl); only the Keycloak URL differs per environment. That URL must equal the hostname the environment's Keycloak overlay serves (derived by the `replace-domain`/`prefix-domain` components, `prod` overrides it in [`envs/prod`](../k8s/apps/identity/keycloak/envs/prod/kustomization.yaml)); the `kustomize-build` check fails when the unit's `keycloak_url` differs from the rendered `Keycloak` or `HTTPRoute` hostname.

## Prerequisites

The unit is developed and proven in `dev`, then promoted to `qa` (the gate) and `prod`: copy the unit directory to the next environment (with its provider lock file, see [`terragrunt/README.md`](../terragrunt/README.md#provider-lock-files)) in a pull request, merge it, and apply `qa`/`prod` from `main` only, never from the branch. `dev` and `qa` have the unit; `prod` and `rebuild` do not yet. Every environment needs its Keycloak instance up and answering on its URL first.

1. **Admin login:** the 1Password item `keycloak-bootstrap-admin#<env>` (the same item the Keycloak Operator uses) with `username` and `password`. The provider logs in with it through the `admin-cli` client. The same account is the break-glass login to Keycloak's `master` realm, see [`keycloak-break-glass.md`](keycloak-break-glass.md).
2. **UCS groups and bind account:** see [UCS setup](#ucs-setup). The bind password goes into the 1Password item `keycloak-ldap-bind#<env>` (field `password`); every environment that applies the unit needs its own item, so copy the `dev` one to `keycloak-ldap-bind#qa` before the first `qa` apply.
3. **Network and trust:** the Keycloak pods must reach both domain controllers on LDAPS **7636** (UCS OpenLDAP; 636 is Samba AD's own LDAP and is not used) and trust the UCS CA (`/etc/univention/ssl/ucsCA/CAcert.pem`, CN `iseja.net Directory Services`), which signs the DCs' certificates. The Keycloak resource mounts it as a truststore from the Secret `keycloak-ucs-ca`, which External Secrets fills from the 1Password item `ucs-ca` (field `ca.pem`, shared by all environments; the certificate is public):

```sh
op item create --vault K8S --category "Secure Note" --title ucs-ca "ca\.pem[text]=$(ssh root@baerbel.dir.iseja.net cat /etc/univention/ssl/ucsCA/CAcert.pem)"
```

Keycloak creates the federation without connecting, so a gap only shows at the first sync.
4. **Reachability from your machine:** the Keycloak URL of the environment must be reachable from where you run Terragrunt (the internal Gateway).

## UCS setup

Done once for the domain (all environments share the directory), as `root` on a domain controller, with the UCS Directory Manager (`udm`). The groups do not exist yet; the realm filters (`memberOf=cn=idm-users,...` and `cn=idm-admins`) admit nobody until they do.

```sh
BASE="dc=dir,dc=iseja,dc=net"

# groups that admit accounts into a realm; members are added after the group exists, so the memberOf overlay fills in
udm groups/group create --position "cn=groups,$BASE" --set name=idm-users  --set description="Accounts allowed into the Keycloak realm iseja"
udm groups/group create --position "cn=groups,$BASE" --set name=idm-admins --set description="Accounts allowed into the Keycloak realm admin"
udm groups/group modify --dn "cn=idm-users,cn=groups,$BASE"  --append users="uid=sebi,cn=users,$BASE"      # plus the other everyday accounts
udm groups/group modify --dn "cn=idm-admins,cn=groups,$BASE" --append users="uid=sebi-adm,cn=users,$BASE"

# read-only bind account: an ordinary user in no realm group; keep the password out of the shell history
read -rs -p "bind password: " PW; echo
udm users/user create --position "cn=users,$BASE" --set username=keycloak-ro --set lastname=keycloak-ro \
  --set description="Read-only LDAP bind for Keycloak" --set password="$PW" --set overridePWHistory=1 --set overridePWLength=1
```

Store the password in the 1Password item `keycloak-ldap-bind#<env>` (field `password`) for every environment that federates. Check the account from a machine that can reach the DC, using the password prompt:

```sh
ldapsearch -x -H ldaps://baerbel.dir.iseja.net:7636 -D "uid=keycloak-ro,cn=users,dc=dir,dc=iseja,dc=net" -W \
  -b "cn=users,dc=dir,dc=iseja,dc=net" "(uid=sebi)" uid entryUUID memberOf
```

It must return the entry with `entryUUID` and, after the group setup, `memberOf: cn=idm-users,...`. Anonymous reads are off in this domain (`ldap/acl/read/anonymous: no`), so a failing bind shows up here first.

The per-application groups `app-<name>-<role>` are not created here: each integration issue creates its own when the application is rolled out, and the `app-*` filter of the group mapper picks them up at the next sync.

## Apply and verify

```sh
source terragrunt/non-prod/eu-central-1/dev/.envrc
cd terragrunt/non-prod/eu-central-1/dev/keycloak-realm
terragrunt plan
terragrunt apply
```

Then, in the Keycloak admin console of each realm, open *User federation* → `ucs` → *Test connection* and *Test authentication*, run *Synchronize all users*, and check that only the accounts of that realm's filter arrive and that their groups appear under *Groups*.

## Caveats

- A user filter decides which realm an account may use. Keep the `iseja` and `admin` filters disjoint.
- Changing a realm name destroys the realm and everything in it, and changes every issuer URL.
- The bind credential and the admin login are part of the Terraform state; the state bucket is access-controlled per environment.
