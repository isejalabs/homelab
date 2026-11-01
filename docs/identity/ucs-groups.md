---
status: current
---

# UCS groups for single sign-on

UCS stays authoritative for users and groups ([ADR 0016](../decisions/0016-identity-and-web-sso.md), point 3); Keycloak reads them read-only ([`keycloak-realms.md`](keycloak-realms.md)). This page owns the **naming scheme** of the groups that carry access, what UCS **nesting** does and does not do for them, and how the old names were migrated. Tracking: [#1715](https://github.com/isejalabs/homelab/issues/1715) (architecture) and [#1727](https://github.com/isejalabs/homelab/issues/1727) (Checkmk, the first user of the groups).

## Naming scheme

Names are lower case, segments separated by `.`, in the form `<kind>.<area>.<name>[.<role>]`. UCS accepts dots in group names (the regular expression of the UDM `name` property allows them, and `fs.onedrive.sebi` already exists).

| Group | Kind | Meaning | Read by Keycloak |
| --- | --- | --- | --- |
| `sec.idm.users` | access | accounts admitted to the realm `iseja` | user filter of the realm |
| `sec.idm.admins` | access | `*-adm` accounts admitted to the realm `admin` | user filter of the realm |
| `sec.app.<app>.<role>`, for example `sec.app.checkmk.admin` | access | one role of one application | group mapper, becomes the `groups` claim |
| `grp.<name>`, for example `grp.family` | people | a set of people, for file shares, mail and the like | no |
| `fs.<...>` | storage | file-share groups, unchanged | no |

- `sec` stands for security: membership of a `sec.*` group grants access to something, so every change to one is an access decision.
- The segment `app` is kept on purpose. The group mapper filter is `(cn=sec.app.*)` (in [`keycloak-realm.hcl`](../../terragrunt/_envcommon/keycloak-realm.hcl)), so only application roles end up in the token; the realm groups `sec.idm.*` are not sent to applications.
- `grp.*` is the naming for groups of people. None exists yet; it is the intended home for "the family" so that it is stated once.

## Nesting

UCS can nest groups, and that works for the Linux and Samba side but **not** for what Keycloak reads. Checked read-only on the domain controller `baerbel` while writing this page, with the group `Domain Users` inside the built-in group `Users`:

| Consumer | Sees nested members | Evidence |
| --- | --- | --- |
| UDM / UMC | yes, as the properties `nestedGroup` and `memberOf` of `groups/group` | `Domain Users` shows `memberOf: cn=Users,cn=Builtin,...` |
| Unix/Linux (`getent group`, NSS) | yes, flattened | `getent group Users` lists twelve accounts; the NSS group cache is generated with nested groups resolved ([UCS manual, groups](https://docs.software-univention.de/manual/latest/en/groups.html)) |
| Samba / AD clients | yes, by AD group semantics | not tested here |
| LDAP `uniqueMember` / `memberUid` | **no** | the LDAP entry `cn=Users,cn=Builtin` has the child group as `uniqueMember` and no user in `uniqueMember` or `memberUid` (count 0), while NSS shows the users |
| LDAP `memberOf` (overlay `univention-ldap-overlay-memberof`) | **no**, direct memberships only | the overlay adds `memberOf` for direct `uniqueMember` values; the UCS forum says the same ([thread](https://help.univention.com/t/ldapsearch-memberof-for-nested-memberships/14091)). Not tested with a throwaway nested pair, which would need two test groups in the live domain |

So the Unix group model is compatible with UCS groups; the gap is only for LDAP clients.

### Consequence for Keycloak

Both ways Keycloak uses a group are direct-membership lookups:

- **Realm admission** is `(memberOf=cn=sec.idm.users,...)`. An account that is only in `grp.family`, with `grp.family` nested in `sec.idm.users`, does not match.
- **The `groups` claim** comes from the LDAP group mapper. Its strategy `LOAD_GROUPS_BY_MEMBER_ATTRIBUTE` (the default, used here) asks for the groups whose `uniqueMember` is the user, and `GET_GROUPS_FROM_USER_MEMBEROF_ATTRIBUTE` reads the user's `memberOf`; both are direct. The third strategy, `LOAD_GROUPS_BY_MEMBER_ATTRIBUTE_RECURSIVELY`, is documented in the Keycloak source as "extension specific to Active Directory" that "likely doesn't work on other LDAP servers" (it uses the matching rule `LDAP_MATCHING_RULE_IN_CHAIN`; [`UserRolesRetrieveStrategy.java`](https://github.com/keycloak/keycloak/blob/main/federation/ldap/src/main/java/org/keycloak/storage/ldap/mappers/membership/UserRolesRetrieveStrategy.java)). The federation here talks to UCS OpenLDAP on 7636, not to the Samba AD LDAP.
- `preserve_group_inheritance` (off here) only imports LDAP nesting as a Keycloak group tree. The mapper returns the groups the user is a member of, not their ancestors ([`GroupLDAPStorageMapper.java`](https://github.com/keycloak/keycloak/blob/main/federation/ldap/src/main/java/org/keycloak/storage/ldap/mappers/membership/group/GroupLDAPStorageMapper.java)), so it does not make `sec.app.*` roles flow down from a parent.

The failure is silent: UMC and `getent` show the nesting working, and the login is refused (or, for a role group, the claim is just missing).

### Rule

**`sec.*` groups contain accounts only, never other groups.** `grp.*` groups may nest wherever the consumer is Unix or Samba. Do not nest a `grp.*` group into a `sec.*` group.

### Options if per-account membership becomes a chore

Not needed at the current size (a handful of accounts per group). If it is, in this order:

1. **Keep as is** and add accounts with `udm groups/group modify --append users=...`; the change is auditable in UCS.
2. **Flatten in UCS**: a small job (listener module or timer) that writes the members of the `grp.*` sources into the `sec.*` groups. UCS does not do this itself, as the LDAP rows above show. Custom code on the domain controllers, so it needs an owner and a test.
3. **Switch the federation to Samba AD LDAP** (port 636) and the recursive strategy: transitive membership works there, but the schema differs (`sAMAccountName`, group object class), the realm filters and mappers change, and it ties the identity provider to the AD side of UCS. A larger change than the problem.

## Migration of the first names

The groups were created as `idm-users`, `idm-admins` and `app-checkmk-{admin,operator,readonly}`. They keep those names in the live domain until the steps below are done (**status: not yet done**; the filters in the code already use the new names). The rename is in place: the UDM property `name` can be changed, and the members stay. The commands, as `root` on a domain controller:

```sh
BASE="dc=dir,dc=iseja,dc=net"

for pair in idm-users:sec.idm.users idm-admins:sec.idm.admins \
            app-checkmk-admin:sec.app.checkmk.admin app-checkmk-operator:sec.app.checkmk.operator app-checkmk-readonly:sec.app.checkmk.readonly; do
  udm groups/group modify --dn "cn=${pair%%:*},cn=groups,$BASE" --set name="${pair##*:}"
done
```

Between the rename and the `terragrunt apply` of the realm filters, the filters match nobody, so run them back to back. The local administrator of Checkmk (`cmkadmin`) is the way in meanwhile ([`checkmk-sso.md`](checkmk-sso.md#break-glass)). In this order:

1. **Merge** the pull request that changes the filters in [`keycloak-realm.hcl`](../../terragrunt/_envcommon/keycloak-realm.hcl) (no apply happens on merge).
2. **UCS:** rename the groups (above) and check `ldapsearch ... "(uid=sebi)" memberOf` returns `cn=sec.idm.users,...` ([`keycloak-realms.md`](keycloak-realms.md#ucs-setup)).
3. **Keycloak:** from `main`, `terragrunt apply` the `keycloak-realm` unit of `dev` and then `qa` ([`keycloak-realms.md`](keycloak-realms.md#apply-and-verify)). In each realm, *User federation → ucs → Mappers → groups → Sync LDAP groups to Keycloak* imports the new names and drops the old ones, then *Sync changed users* (or wait up to an hour, see [`checkmk-sso.md`](checkmk-sso.md#changing-who-has-access)).
4. **Checkmk:** in each SAML connection of `dev_k8s` and `qa_k8s` (four in all) replace the group names in the role and contact group mapping by the new ones ([`checkmk-sso.md`](checkmk-sso.md#checkmk-side)).
5. **Verify** a login as `sebi`, `sebi-adm` and `mary` in both sites.

To roll back, rename the groups back and revert the pull request.
