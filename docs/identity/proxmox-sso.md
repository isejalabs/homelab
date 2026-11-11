---
status: current
---

# Proxmox human SSO

Browser sign-in to the Proxmox web interface through the identity provider of [ADR 0016](../decisions/0016-identity-and-web-sso.md). Tracking: [#1728](https://github.com/isejalabs/homelab/issues/1728); first scenario `bob-adm` with administrative rights [#2235](https://github.com/isejalabs/homelab/issues/2235); operator and read-only roles for `bob` and `alice` [#2236](https://github.com/isejalabs/homelab/issues/2236); rules of the rollout [#2198](https://github.com/isejalabs/homelab/issues/2198).

**Status (2026-11-10):** live. The realms `kc-admin` and `kc-iseja`, the three groups, the `Operator` role and the ACLs on `/` are applied by the Terragrunt unit `prod/proxmox-access` (module `proxmox-access` 0.1.0), and the owner confirmed the logins of `bob-adm`, `bob` and `alice`, of the AD realm and of `root@pam` on 2026-11-10. The AD realm stays the default and `root@pam` and every API token are untouched; removing the AD realm is a separate decision. What was verified, and what is still open, is under [Verification](#verification).

**On this page:** [Inventory](#inventory) · [Reuse before build](#reuse-before-build) · [Design](#design) · [Roles](#roles) · [MFA](#mfa) · [Break-glass](#break-glass) · [Rollout](#rollout) · [Verification](#verification) · [Decisions](#decisions)

## Inventory

Read on 2026-11-08 with `pveversion`, `pvecm`, `pveum ... list` and `/etc/pve/domains.cfg` on `pve4` (no write).

| Fact | Value |
| --- | --- |
| Clusters in scope | **One**, `ISEJA-Lab` (4 nodes: `pve1`, `pve4`, `pve5`, `pve6`; the Terragrunt `proxmox.endpoint` is `https://pve4.home.iseja.net:8006`). Realms, groups, roles and ACLs are cluster-wide (`/etc/pve`), so one apply covers all four nodes. The Proxmox Backup Server `polina` is a separate product and not in scope. |
| Version | `pve-manager 9.2.26`, kernel 7.0.14. OpenID Connect realms with a groups claim need 8.1 or later. |
| Realms | `DIR.ISEJA.NET` (type `ad`, servers `adelheid` and `baerbel`, **the default realm**), `pam`, `pve`. No OpenID Connect realm yet. |
| Users | `bob-adm@DIR.ISEJA.NET` (the only human, TOTP enrolled in Proxmox), `root@pam`, and API-only users in realm `pve`: `terraform@pve`, `checkmk@pve`, and `kubernetes-csi@pve` plus the `dev`/`qa`/`prod`/`rebuild`/`src`/`dbg` variants. |
| Groups | `Admin` (member `bob-adm@DIR.ISEJA.NET`; ACLs `Administrator` and `PVEAdmin` on `/`), `checkmk` (member `checkmk@pve`; `PVEAuditor` on `/`). |
| Custom roles | `Terraform`, `CSI`, `<env>-CSI`. |
| Who manages it today | Realms, users, groups and the `Admin` and `checkmk` ACLs are **by hand**; nothing in this repository or in the Salt repository (`salt-iseja.net`, which manages repositories, certificates and PCI passthrough on the nodes) declares them. The CSI role, user and token are code (`terraform-proxmox-talos`, `bootstrap/proxmox-csi-plugin`, `<env>-` prefixed in this one cluster). `terraform@pve` has `Administrator` on `/`, which includes `Realm.Allocate`, so the existing provider token can manage realms. |
| TLS | Every node has a Let's Encrypt certificate for its own FQDN (`pveN.home.iseja.net`) and no cluster alias name. From `pve4`, `https://auth.iseja.net` resolves to `10.8.8.80` and answers with a verified certificate (the discovery document of realm `admin`, HTTP 200). |

## Reuse before build

| Option | Result |
| --- | --- |
| The `bpg/proxmox` provider, already used by `vms`, `talos-proxmox` and the CSI bootstrap | **Taken.** Version 0.120.0 (2026-11-02) has `proxmox_realm_openid` (with the write-only `client_key_wo`, so the secret stays out of the state), `proxmox_virtual_environment_group`, `_role` and `proxmox_acl`. Documented fields checked: issuer, client, username claim, groups claim, `autocreate`, `groups_autocreate`, `groups_overwrite`, scopes, `default`. |
| A registry module for Proxmox access control | Not searched further: three resource types do not justify a dependency. |
| The Proxmox web interface or `pveum` by hand | Rejected: the realm, groups and ACLs are the access control of the whole cluster and belong in Git. Kept only for [break-glass](#break-glass). |
| Salt on the nodes (`salt-iseja.net`) | Rejected: it manages the host, not the cluster-wide access configuration, and has no secret path for the client key. |

The outcome is the module [`proxmox-access`](https://github.com/isejalabs/terraform-modules/tree/proxmox-access-v0.1.0/modules/proxmox-access) ([terraform-modules PR](https://github.com/isejalabs/terraform-modules/pull/96), released as `proxmox-access-v0.1.0`), a thin wrapper of those resources with validation and offline tests, used from the Terragrunt unit [`proxmox-access`](../../terragrunt/prod/eu-central-1/prod/proxmox-access/terragrunt.hcl) for the cluster.

## Design

- **One OpenID Connect realm per Keycloak realm.** Proxmox accepts several, and the login page offers them in a realm drop-down. `kc-admin` (issuer `https://auth.iseja.net/realms/admin`, accounts `*-adm`) comes first ([#2235](https://github.com/isejalabs/homelab/issues/2235)); `kc-iseja` follows for `bob` and `alice` ([#2236](https://github.com/isejalabs/homelab/issues/2236)). The realm ID becomes the suffix of the user ID (`bob-adm@kc-admin`) and of every group name, so it is kept short.
- **Issuer: the `prod` Keycloak.** The cluster is one and real, and ADR 0016 (point 2) lets `prod` serve the out-of-cluster services. The same rule as for Checkmk applies ([`checkmk-sso.md`](checkmk-sso.md)): `dev` and `qa` prove the client and the unit, they do not get rights on the production hypervisors.
- **Users: autocreate at the first login; rights only from groups.** `autocreate = true` and `groups_autocreate = false`: a user exists without any right until the claim puts them into a group that is declared in code. The alternative, pre-creating each user, adds an entry per person to the code and gains nothing, since the realm filter (`sec.idm.admins`) already decides who may sign in. An account outside the group gets an empty interface.
- **Groups: claim `groups`, replaced at every login** (`groups_overwrite = true`), so removing someone from the UCS group takes effect at the next login. Proxmox appends the realm ID to the claim value, so the UCS group `sec.app.proxmox.admin` becomes the Proxmox group `sec.app.proxmox.admin-kc-admin`, declared in code with its ACL. Value and realm: [`proxmox-access` README](https://github.com/isejalabs/terraform-modules/blob/proxmox-access-v0.1.0/modules/proxmox-access/README.md#how-the-login-maps-to-rights).
- **Keycloak client:** confidential, standard flow, `groups` as a default client scope, username from `preferred_username`. Redirect URIs: Proxmox uses the URL the user opened as the redirect URI, so one entry per node, `https://pve{1,4,5,6}.home.iseja.net:8006` (and the same with a trailing `/` if Keycloak requires it exactly), and web origins for the same hosts. The secret goes into a 1Password item as decided in [#2227](https://github.com/isejalabs/homelab/issues/2227); the module reads it from there.
- **The login page default stays `DIR.ISEJA.NET`** until the OpenID Connect realm is proven; the new realm is chosen from the drop-down. Switching the default is a later, separate step.
- **UCS:** the group `sec.app.proxmox.admin` with member `bob-adm` (naming: [`ucs-groups.md`](ucs-groups.md)). Needs the owner's explicit go; the group mapper (`(cn=sec.app.*)`) picks it up at the next sync. `sec.app.proxmox.operator` and `sec.app.proxmox.readonly` follow with [#2236](https://github.com/isejalabs/homelab/issues/2236).

## Roles

| Account | Realm | UCS group | Proxmox group (realm `kc-<realm>`) | Role | Path |
| --- | --- | --- | --- | --- | --- |
| `bob-adm` | `admin` | `sec.app.proxmox.admin` | `sec.app.proxmox.admin-kc-admin` | `Administrator` | `/` |
| `bob` | `iseja` | `sec.app.proxmox.operator` | `sec.app.proxmox.operator-kc-iseja` | custom `Operator` (below) | `/` or the pool of guests it may operate |
| `alice` | `iseja` | `sec.app.proxmox.readonly` | `sec.app.proxmox.readonly-kc-iseja` | `PVEAuditor` | `/` |

`Administrator` rather than `PVEAdmin` for the administrator: it is what the existing `Admin` group has (both are granted today), and it is the only built-in role with `Permissions.Modify`, `Realm.Allocate` and `Sys.Modify`. Verified by listing the roles on the cluster.

`Operator` (agreed in [#2236](https://github.com/isejalabs/homelab/issues/2236)): the privileges of `PVEAuditor` plus `VM.Console`, `VM.PowerMgmt` and `VM.Snapshot`; **not** `VM.Snapshot.Rollback`, `VM.Config.*`, `VM.Allocate`, `VM.Backup`, `VM.GuestAgent.File*` (file write inside the guest), `Datastore.Allocate*`, `Sys.Console` (shell on the node), `Sys.Modify`, `Sys.PowerMgmt`, `Pool.Allocate`, `SDN.*`, `Permissions.Modify`, `User.Modify`, `Group.Allocate`, `Realm.*`. The built-in `PVEVMUser` is not used because it includes guest-agent file writes, backups and CD-ROM changes. A console is a login prompt of the guest, not root on it.

Checks for [#2236](https://github.com/isejalabs/homelab/issues/2236), against the effective permissions of the real accounts (result under [Verification](#verification)): neither account can create, change or see users and realms, cannot create an API token with more rights than the account has (a token cannot exceed its owner), cannot open a node shell, and the Datacenter views show only what `PVEAuditor` shows.

## MFA

| Login | Second factor today |
| --- | --- |
| `bob-adm@DIR.ISEJA.NET` | TOTP enrolled in Proxmox (`pveum user tfa list`: one `totp` entry), applies to AD realm logins |
| Any OpenID Connect realm | **None from Proxmox.** Proxmox's own two-factor configuration applies to its own realms; the OpenID Connect login is authenticated at the identity provider only. Consistent with the test logins: `pveum user tfa list` has an entry only for `bob-adm@DIR.ISEJA.NET` and none for any `@kc-admin` or `@kc-iseja` user, yet those users signed in. |

So the second factor of the new login has to come from Keycloak. The module `keycloak-realm` can require one per realm (`second_factor`, version 0.5.0, [#2206](https://github.com/isejalabs/homelab/issues/2206)), but [`keycloak-realm.hcl`](../../terragrunt/_envcommon/keycloak-realm.hcl) does not set it yet. **Gate (met):** `Administrator` is granted to the OpenID Connect realm only after the realm `admin` asks `bob-adm` for WebAuthn or TOTP ([#2214](https://github.com/isejalabs/homelab/pull/2214), applied in `prod` on 2026-11-08), otherwise the new path would be weaker than the old one (password only against UCS). Observed at the first login of `bob-adm` on 2026-11-10: Keycloak sent the account through the enrollment of a WebAuthn authenticator before signing in; see [Verification](#verification).

## Break-glass

- `root@pam` (realm `Linux PAM`) works without the identity provider, the cluster or UCS' being reachable beyond the node itself, and its TOTP/password are not touched. Keycloak runs as VMs on this cluster and UCS on two of its guests (`adelheid`, `baerbel`), so an outage of either is exactly the case it covers.
- The AD realm and its TOTP stay until the OpenID Connect realm is proven in [#2235](https://github.com/isejalabs/homelab/issues/2235); removing it is a separate decision.
- Locked-out recovery without the web interface: `ssh root@pveN`, then `pveum realm delete kc-admin` removes the realm, or `pveum acl delete / --groups <group> --roles <role>` removes a grant; `pveum realm list` shows what exists. Neither touches the other realms.
- **Test with a second session.** Before any apply that changes realms, keep a logged-in `root@pam` session (and the `bob-adm@DIR.ISEJA.NET` one) open in another browser, and check `root@pam` after the apply.

## Rollout

Each step only after the previous one, and each step that changes the live cluster needs the owner's go (given on 2026-11-09). All steps are done (2026-11-09 and 2026-11-10): the clients `proxmox-iseja` and `proxmox-admin` exist in `prod`, the UCS groups `sec.app.proxmox.admin|operator|readonly` and their members were created by the owner, and the unit is applied from `main`.

1. [#2227](https://github.com/isejalabs/homelab/issues/2227) merged: `oidc_clients` available; a throwaway client proven in `dev`.
2. Add the client `proxmox` to the `prod` (and, for testing the unit, `dev`) `keycloak-realm` input; apply from `main`.
3. UCS: create `sec.app.proxmox.admin`, add `bob-adm`; sync the Keycloak group mapper. Owner's go.
4. Release the module, add the Terragrunt unit `proxmox-access` for the cluster with realm `kc-admin`, group, and the `Administrator` ACL; `plan` first (it must show only new resources, nothing on the AD realm, `root@pam`, users or tokens), then apply from `main`.
5. Test: `bob-adm` through `kc-admin` (administrative rights), an account outside the group (no rights), `root@pam` and the AD login still work, automation unaffected (`terragrunt plan` of a `vms` unit and the Checkmk and CSI tokens still authenticate).
6. [#2236](https://github.com/isejalabs/homelab/issues/2236): UCS groups, realm `kc-iseja`, `Operator` role, `PVEAuditor` for `alice`; verify with the real accounts.

## Verification

Applied on 2026-11-09 from `main` ([PR 2259](https://github.com/isejalabs/homelab/pull/2259)): 9 added, 0 changed, 0 destroyed. Checked on 2026-11-10 on `pve1` with read-only `pveum` commands, plus the owner's confirmation of the logins.

| Check | Result | Evidence |
| --- | --- | --- |
| Realms | `kc-admin` and `kc-iseja` exist; `DIR.ISEJA.NET` is still the default | `pveum realm list` |
| `bob-adm` through `kc-admin` | Signs in; effective rights are those of `Administrator` (47 privileges on all 38 paths, including `Permissions.Modify`, `Realm.Allocate`, `Sys.Console`) | owner's confirmation; `pveum user permissions bob-adm@kc-admin` |
| `bob` through `kc-iseja` | Signs in; exactly the 10 privileges of `Operator` on every path | owner's confirmation; `pveum user permissions bob@kc-iseja` |
| `alice` through `kc-iseja` | Signs in; exactly the 7 privileges of `PVEAuditor` on every path | owner's confirmation; `pveum user permissions alice@kc-iseja` |
| Operator cannot manage users, realms, permissions or open a node shell | `Operator` has none of `User.Modify`, `Group.Allocate`, `Realm.*`, `Permissions.Modify`, `Sys.Console`, `Sys.Modify`. A token cannot exceed its owner's rights, so it cannot carry more | `pveum user permissions` as above |
| An account outside the groups gets no rights | `toni@kc-iseja` was autocreated at its first login and has no permission on any path | `pveum user permissions toni@kc-iseja` |
| AD login and `root@pam` still work | Confirmed by the owner. The apply changed neither realm | owner's confirmation; apply result |
| API tokens and automation unaffected | The unit's own `terragrunt plan` with the `terraform@pve` token after the apply reports no changes | `terragrunt plan` on 2026-11-10 |
| Proxmox asks no second factor for OpenID Connect logins | No TFA entry exists for any OpenID Connect user, and they signed in | `pveum user tfa list` |

The second factor comes from Keycloak: the first login of `bob-adm` through `kc-admin` required enrolling a WebAuthn authenticator (reported by the owner on 2026-11-10), as the `second_factor` setting of the realm `admin` is meant to do. Later logins use that authenticator.

## Decisions

Confirmed by the owner on 2026-11-09:

| # | Decision | Outcome |
| --- | --- | --- |
| 1 | Which Keycloak issues for the single cluster | `prod`; `dev`/`qa` prove the unit without rights on the hypervisors |
| 2 | Autocreate users or pre-create them | Autocreate, rights only from groups |
| 3 | Realm IDs | `kc-admin`, `kc-iseja` (comments name the Keycloak realm) |
| 4 | Where the unit lives | One `proxmox-access` unit for the cluster under `terragrunt/prod/eu-central-1/prod/` |
| 5 | MFA gate | `second_factor` on the realm `admin`, applied in `prod` ([#2214](https://github.com/isejalabs/homelab/pull/2214)) before the `Administrator` grant |
| 6 | Scope of the operator and the read-only account | Whole cluster (ACL path `/`) |
