---
status: current
---

# Keycloak realms

The realm content of the identity provider ([ADR 0016](../decisions/0016-identity-and-web-sso.md), point 7) is managed by the Terragrunt unit `keycloak-realm` per environment, which uses the module [`keycloak-realm`](https://github.com/isejalabs/terraform-modules/tree/main/modules/keycloak-realm) from `isejalabs/terraform-modules`. The Keycloak server itself is deployed by Flux (`k8s/apps/identity/keycloak`); this unit only fills it.

The unit creates the realms `iseja` (everyday accounts) and `admin` (`*-adm` accounts), each with a **read-only** LDAP federation to UCS and a `groups` client scope. The unit can also register SAML clients (`saml_clients`, one per application and realm) for applications that only speak SAML; the Checkmk sites use it, see [`checkmk-sso.md`](checkmk-sso.md). Kerberos and the OIDC clients come with [#1827](https://github.com/isejalabs/homelab/issues/1827) and the per-service integrations, the second factor (WebAuthn, TOTP) is part of the unit, see [`keycloak-mfa.md`](keycloak-mfa.md).

The directory facts (base DN, domain controllers, bind account, group names) and the realm definitions are stated once in [`terragrunt/_envcommon/keycloak-realm.hcl`](../../terragrunt/_envcommon/keycloak-realm.hcl); only the Keycloak URL differs per environment. That URL must equal the hostname the environment's Keycloak overlay serves (derived by the `replace-domain`/`prefix-domain` components, `prod` overrides it in [`envs/prod`](../../k8s/apps/identity/keycloak/envs/prod/kustomization.yaml)); the `kustomize-build` check fails when the unit's `keycloak_url` differs from the rendered `Keycloak` or `HTTPRoute` hostname.

## Prerequisites

The unit is developed and proven in `dev`, then promoted to `qa` (the gate) and `prod`: copy the unit directory to the next environment (with its provider lock file, see [`terragrunt/README.md`](../../terragrunt/README.md#provider-lock-files)) in a pull request, merge it, and apply `qa`/`prod` from `main` only, never from the branch. `dev`, `qa` and `prod` have the unit (`prod`'s were applied on 2026-11-08); `rebuild` does not. Every environment needs its Keycloak instance up and answering on its URL first.

1. **Automation client:** the 1Password item `keycloak-terragrunt#<env>` (client ID as `username`, client secret as `password`), written by the unit `keycloak-automation`, see [Automation client](#automation-client). The provider logs in with it through the client-credentials grant. It is not the break-glass administrator `keycloak-bootstrap-admin#<env>` of Keycloak's `master` realm ([`keycloak-break-glass.md`](keycloak-break-glass.md)), which routine plan and apply do not use any more.
2. **UCS groups and bind account:** see [UCS setup](#ucs-setup). The bind password goes into the 1Password item `keycloak-ldap-bind#<env>` (field `password`); every environment that applies the unit needs its own item, so copy the `dev` one to `keycloak-ldap-bind#qa` before the first `qa` apply.
3. **Network and trust:** the Keycloak pods must reach both domain controllers on LDAPS **7636** (UCS OpenLDAP; 636 is Samba AD's own LDAP and is not used) and trust the UCS CA (`/etc/univention/ssl/ucsCA/CAcert.pem`, CN `iseja.net Directory Services`), which signs the DCs' certificates. The Keycloak resource mounts it as a truststore from the Secret `keycloak-ucs-ca`, which External Secrets fills from the 1Password item `ucs-ca` (field `ca.pem`, shared by all environments; the certificate is public):

```sh
op item create --vault K8S --category "Secure Note" --title ucs-ca "ca\.pem[text]=$(ssh root@baerbel.dir.iseja.net cat /etc/univention/ssl/ucsCA/CAcert.pem)"
```

Keycloak creates the federation without connecting, so a gap only shows at the first sync.
4. **Reachability from your machine:** the Keycloak URL of the environment must be reachable from where you run Terragrunt (the internal Gateway).

## UCS setup

Done once for the domain (all environments share the directory), as `root` on a domain controller, with the UCS Directory Manager (`udm`). Group names follow [`ucs-groups.md`](ucs-groups.md); the groups exist in the live domain, the commands are for a fresh domain. The realm filters (`memberOf=cn=sec.idm.users,...` and `cn=sec.idm.admins`) admit nobody until they do.

```sh
BASE="dc=dir,dc=iseja,dc=net"

# groups that admit accounts into a realm; members are added after the group exists, so the memberOf overlay fills in
udm groups/group create --position "cn=groups,$BASE" --set name=sec.idm.users  --set description="Accounts allowed into the Keycloak realm iseja"
udm groups/group create --position "cn=groups,$BASE" --set name=sec.idm.admins --set description="Accounts allowed into the Keycloak realm admin"
udm groups/group modify --dn "cn=sec.idm.users,cn=groups,$BASE"  --append users="uid=sebi,cn=users,$BASE"      # plus the other everyday accounts
udm groups/group modify --dn "cn=sec.idm.admins,cn=groups,$BASE" --append users="uid=sebi-adm,cn=users,$BASE"

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

It must return the entry with `entryUUID` and, after the group setup, `memberOf: cn=sec.idm.users,...`. Anonymous reads are off in this domain (`ldap/acl/read/anonymous: no`), so a failing bind shows up here first.

The per-application groups `sec.app.<name>.<role>` (naming: [`ucs-groups.md`](ucs-groups.md#naming-scheme)) are not created here: each integration issue creates its own when the application is rolled out, and the `sec.app.*` filter of the group mapper picks them up at the next sync.

## Automation client

Plan and apply of `keycloak-realm` log in as a dedicated service-account client `terragrunt` in the `master` realm, not as the break-glass administrator, so whoever runs Terragrunt does not hold the emergency credential ([#1942](https://github.com/isejalabs/homelab/issues/1942)). The client is created by the Terragrunt unit `keycloak-automation` through the module [`keycloak-automation`](https://github.com/isejalabs/terraform-modules/tree/main/modules/keycloak-automation): a confidential client that can only use the client-credentials grant, with the realm role `create-realm` and the realm-management roles of the `iseja-realm` and `admin-realm` clients (`existing_realms`; there is no composite `realm-admin` in these clients), nothing else; the generated secret goes into the 1Password item `keycloak-terragrunt#<env>`.

The unit is the one place where the break-glass administrator (`keycloak-bootstrap-admin#<env>`) is still used by Terragrunt, and it runs rarely:

| When | What |
| --- | --- |
| First setup of an environment, **before** `keycloak-realm` | `terragrunt apply` in `keycloak-automation`. On a fresh instance without realms leave `existing_realms` empty: the client creates the realms itself and Keycloak makes it their administrator. |
| Rotating the secret | Set `secret_rotation = "<date>"` in the `inputs` of the unit (the module default is `initial`) and apply `keycloak-automation`. Keycloak generates the new secret and the 1Password item is updated in the same apply; the next `keycloak-realm` run reads it. The old secret stops working at once. |
| After a restore of a dump ([restore](keycloak-backup-restore.md#restore)), also one from another environment | The restored `master` realm carries that dump's `terragrunt` client and secret, not this environment's. Sign in with the break-glass administrator **of the restored data**, then apply `keycloak-automation`: the unit reads the restored secret from Keycloak and writes it to the 1Password item, so no changed `secret_rotation` is needed (use one only to get a fresh secret). If the restored realm has no such client, the apply recreates it (not tried). Verified in `dev` for a dump of the same environment taken before a rotation (2026-11-07): after the restore `keycloak-realm` failed with `401 Unauthorized` at the login, and one plain apply of `keycloak-automation` (one change, the item's password) made `keycloak-realm` plan clean again. A dump of **another** environment is different: the client then has another id and the apply fails with `409 Client terragrunt already exists`; import the client first, and expect `keycloak-realm` to need imports as well, see [`keycloak-backup-restore.md`](keycloak-backup-restore.md#a-qa-dump-in-dev) ([#2201](https://github.com/isejalabs/homelab/issues/2201)). |

Verified in `dev` (2026-11-01 and 2026-11-02, applied from the branch with the module from its branch): the unit created the client, its roles and the 1Password item; `keycloak-realm` refreshed every resource it manages with the client alone and applied a write (a brute-force setting of both realms, changed and reverted) without a missing role; changing `secret_rotation` replaced the secret and the 1Password item in one apply, after which `keycloak-realm` logged in with the new one. Verified in `qa` (2026-11-02, applied from `main`): the unit created the client, its roles and the 1Password item, and `keycloak-realm` plans with no changes using the client alone. Both units pin their module to a release tag, see [`terragrunt/README.md`](../../terragrunt/README.md#automation-client-keycloak-automation). The secret is part of the state of both units, see [Caveats](#caveats).

**Registered environments:** `dev`, `qa` and `prod` have the units `keycloak-automation` and `keycloak-realm`; `rebuild` has neither yet. The `prod` units were registered with the enabling pull request of the `prod` go-live ([#2196](https://github.com/isejalabs/homelab/issues/2196)): both copy the `qa` unit with its tracked provider lock file, `keycloak_url` is `https://auth.iseja.net`, `existing_realms` is empty (the instance has no realms yet) and `keycloak-realm` has no `saml_clients` yet (the Checkmk sites `prod_k8s` and `prod` are not set up for SSO, see [`checkmk-sso.md`](checkmk-sso.md)). They were applied from `main` on 2026-11-08, once Keycloak answered on its URL: `keycloak-automation` first (client `terragrunt`, the 1Password item `keycloak-terragrunt#prod`, [#2200](https://github.com/isejalabs/homelab/issues/2200)), then `keycloak-realm` (the realms `iseja` and `admin` with their UCS federation); both plan clean afterwards.

## Apply and verify

```sh
source terragrunt/non-prod/eu-central-1/dev/.envrc
cd terragrunt/non-prod/eu-central-1/dev/keycloak-realm
terragrunt plan
terragrunt apply
```

Then, in the Keycloak admin console of each realm, open *User federation* → `ucs` → *Test connection* and *Test authentication*, run *Synchronize all users*, and check that only the accounts of that realm's filter arrive and that their groups appear under *Groups*.

## UCS failover test in `prod`

The connection URL of both realms lists `baerbel` first, then `adelheid` ([#1956](https://github.com/isejalabs/homelab/issues/1956)). Domain controllers were not shut down for the test (a planned outage of each would affect DNS, DHCP and LDAP for everything else, see [#1821](https://github.com/isejalabs/homelab/issues/1821)); the traffic from the Keycloak pod to one domain controller was dropped instead, and a real shutdown of `baerbel` was done once at the end for comparison.

**Method.** A temporary `CiliumNetworkPolicy` in the namespace `keycloak`, applied with `kubectl apply` (not in Git, not managed by Flux) and deleted afterwards, named `tmp-failover-block-<dc>`, selecting the pod by `app=keycloak`, `app.kubernetes.io/instance=keycloak` and `app.kubernetes.io/managed-by=keycloak-operator`:

```yaml
spec:
  endpointSelector: {matchLabels: {app: keycloak, app.kubernetes.io/instance: keycloak, app.kubernetes.io/managed-by: keycloak-operator}}
  egress:
    - toEntities: [all]
  egressDeny:
    - toCIDR: [10.7.1.102/32]   # baerbel; adelheid is 10.7.1.101/32
      toPorts:
        - ports: [{port: "7636", protocol: TCP}, {port: "7389", protocol: TCP}]
```

A deny rule beats any allow rule, so the policy drops only LDAP(S) to that one address. **The `egress` allow-all rule is required:** a policy with only `egressDeny` still switches the pod to default-deny for egress, and the first attempt therefore also cut the database and DNS for 41 s (20:12:06 to 20:12:47 UTC) until it was deleted; Keycloak stayed `Ready`. A plain Kubernetes `NetworkPolicy` is allow-only and cannot express this at all.

**Proof that the block bites**, before any login counted: `kubectl exec keycloak-0 -- bash -c 'timeout 4 bash -c "</dev/tcp/<ip>/7636"'` (the image has no `nc`) failed for the blocked address while the other domain controller, `keycloak-db-rw:5432` and cluster DNS still connected. Dropped packets are not rejected, so the client sees a connect timeout; the Keycloak log shows `SocketTimeoutException: Connect timed out`.

| UTC (2026-11-08) | State | Result |
| --- | --- | --- |
| 20:03 to 20:05 | No block (baseline): `sebi` in `iseja`, `sebi-adm` in `admin` | Both logged in, no noticeable delay |
| 20:13 to 20:17 | Both domain controllers blocked | `sebi-adm` login failed: `LDAP server is unavailable for provider [ucs]`, `LOGIN_ERROR`; proves the test measures the federation |
| 20:17 to 20:24 | Only `baerbel` blocked | Logins worked via `adelheid`, 41 s each (reported by the owner) |
| 20:24 to 20:27 | Only `adelheid` blocked | Logins worked without noticeable delay |
| about 20:27 to 20:33 | `baerbel` powered off for real by the owner, no policy | Logins worked, 40 to 41 s |
| 20:33 | `baerbel` back, no policy | Both domain controllers, the database and DNS reachable from the pod; `kubectl get cnp,ccnp -A` empty |

The simulated outage (dropped packets) and the real shutdown behaved the same, so the policy is a realistic stand-in. Failing over costs about 41 s per login while the first domain controller is down, which matches roughly four 10 s timeouts (`connectionTimeout` and `readTimeout` of the federation are both 10 s); where the attempts come from was not traced. With only the second domain controller down the first answers and nothing is lost. Lowering the connection timeout would shorten the failover but also risks false failures on a slow bind; it was not changed.

## Caveats

- A user filter decides which realm an account may use. Keep the `iseja` and `admin` filters disjoint.
- The filters and the group mapper read direct group membership only, so `sec.*` groups must contain accounts, not other groups; see [`ucs-groups.md`](ucs-groups.md#nesting).
- Changing a realm name destroys the realm and everything in it, and changes every issuer URL.
- The bind credential and the automation client's secret are part of the state of `keycloak-realm`, and the client secret and the break-glass admin login of the state of `keycloak-automation`; the state bucket is access-controlled per environment.
