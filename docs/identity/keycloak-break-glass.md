---
status: current
---

# Keycloak break-glass access

**Choose a task:** sign in when the realms or UCS are down under [Sign in to the admin console](#sign-in-to-the-admin-console); the credential does not work under [When the credential does not work](#when-the-credential-does-not-work); change it under [Rotate the credential](#rotate-the-credential).

**On this page:** [Overview](#overview) · [Where the credential lives](#where-the-credential-lives) · [Sign in to the admin console](#sign-in-to-the-admin-console) · [When the credential does not work](#when-the-credential-does-not-work) · [Rotate the credential](#rotate-the-credential) · [Verified and not verified](#verified-and-not-verified) · [Open points](#open-points)

## Overview

The identity provider never protects its own recovery path ([ADR 0016](../decisions/0016-identity-and-web-sso.md), point 9; [design plan](../plans/2026-10-identity-claude.md)). Keycloak's own administration therefore does not go through the realms `iseja` and `admin`, which need UCS to log anybody in, but through one local account in the built-in **`master` realm**: the *bootstrap admin*.

- The `master` realm has no user federation. The Terragrunt unit [`keycloak-realm`](keycloak-realms.md) manages only `iseja` and `admin`, so a login in `master` needs neither UCS, nor the other realms, nor the Terragrunt state.
- It does need the Keycloak pod, its database, the internal Gateway with the Keycloak route, and a certificate. When the cluster itself is down there is no break-glass path to Keycloak; the services in the break-glass list of the ADR (Proxmox, OPNsense, TrueNAS, RustFS, `talosctl`) have their own local logins, which are not covered here.
- Routine automation does not use this account: the Terragrunt unit `keycloak-realm` logs in as the service-account client `terragrunt` ([automation client](keycloak-realms.md#automation-client)). Only the unit `keycloak-automation` (first setup, rotating the client secret, recreating the client after a restore) logs in with the account described here (`admin_item_title` in [`terragrunt/_envcommon/keycloak-automation.hcl`](../../terragrunt/_envcommon/keycloak-automation.hcl)).

| Situation | Path |
| --- | --- |
| UCS or one domain controller down, a realm misconfigured, a realm deleted by mistake | [Sign in to `master`](#sign-in-to-the-admin-console) and fix it there |
| `iseja`/`admin` user locked out of their MFA | Sign in to `master`, open the realm, remove the credential of that user |
| 1Password item and Keycloak disagree | [When the credential does not work](#when-the-credential-does-not-work) |
| Database lost | [Restore](keycloak-backup-restore.md#restore); the restored `master` realm carries the admin password as of the dump |

## Where the credential lives

| Where | What |
| --- | --- |
| 1Password, vault `K8S`, item `keycloak-bootstrap-admin#<env>` | The source of truth. Fields `username` and `password`. Exists for `dev` and `qa`; the `prod` and `rebuild` items are created when those environments register Keycloak. |
| `ExternalSecret` `keycloak-bootstrap-admin` in namespace `keycloak` | Extracts the whole item (key `keycloak-bootstrap-admin#<env>`, set per environment in `k8s/apps/identity/keycloak/envs/<env>/`), refresh interval 1 h. |
| `Secret` `keycloak-bootstrap-admin` in namespace `keycloak` | Created by the ExternalSecret. Carries `username`, `password` and `notesPlain` (the item's notes field). |
| Keycloak pod `keycloak-0` | The Keycloak Operator maps the Secret (`spec.bootstrapAdmin.user.secret` in [`keycloak.yaml`](../../k8s/apps/identity/keycloak/base/keycloak.yaml)) to the environment variables `KC_BOOTSTRAP_ADMIN_USERNAME` and `KC_BOOTSTRAP_ADMIN_PASSWORD`. |

**These variables take effect once.** Keycloak creates the account only on the first start against an empty database, when it creates the `master` realm; the operator documents the field as "used only for initial cluster creation". Changing the Secret or the 1Password item later does **not** change the password inside Keycloak. The item is only correct as long as nobody changed the password in Keycloak without updating it; see [Rotate the credential](#rotate-the-credential).

Read the credential, without writing it anywhere:

```sh
op item get 'keycloak-bootstrap-admin#<env>' --vault K8S --fields label=username,label=password --reveal
```

If 1Password is unreachable but the cluster is up, the synced Secret has the same values (it stays in place when the 1Password Connect server is down):

```sh
kubectl get secret keycloak-bootstrap-admin -n keycloak --context admin@<env>-homelab -o jsonpath='{.data.password}' | base64 -d
```

## Sign in to the admin console

The `master` realm answers on the same hostname as the other realms; only the realm in the URL differs.

| Environment | Admin console of `master` |
| --- | --- |
| `dev` | `https://dev-auth.dev.iseja.net/admin/master/console/` |
| `qa` | `https://qa-auth.qa.iseja.net/admin/master/console/` |
| `prod` | `https://auth.iseja.net/admin/master/console/` (not deployed yet) |

Sign in with the `username` and `password` of the item. Do not pick the realm selector `iseja` or `admin`: those delegate the password check to UCS.

Once in, the realms `iseja` and `admin` appear in the realm selector. What usually helps:

- *User federation* → `ucs`: test connection and authentication, or fix the connection URL or bind credential for the moment (the Terragrunt unit overwrites a manual change at its next apply, so mirror the fix in the unit afterwards).
- *Users* → the person → *Credentials*: delete a lost WebAuthn key or TOTP so the person can enroll again. This is the break-glass step the [restore documentation](keycloak-backup-restore.md) refers to for the `admin` realm.

### When the Gateway or the certificate is down

The Keycloak pod itself answers on the Service `keycloak-service` (port 8080, plain HTTP; TLS ends at the Gateway). This gets the API and the discovery documents out of a running pod:

```sh
kubectl port-forward -n keycloak svc/keycloak-service 18080:8080 --context admin@<env>-homelab
curl -s http://localhost:18080/realms/master/.well-known/openid-configuration
```

The hostname is fixed in the Keycloak resource, so Keycloak builds every redirect from it (the discovery document shows `http://<hostname>:18080/...`). The admin console in a browser is therefore **not expected to work** through the port-forward and has not been tried; use `kcadm.sh` inside the pod (`kubectl exec -it keycloak-0 -n keycloak -- /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user <username>`) or fix the Gateway.

## When the credential does not work

Typical causes, most likely first:

1. **The password was changed in Keycloak, but not in 1Password** (or the other way round). Another `master` admin, if one exists, resets it under *Users* → `<username>` → *Credentials*. The Terragrunt unit `keycloak-automation` fails the same way (login error from the provider), which is how it usually shows up; `keycloak-realm` is not affected, it uses the automation client.
2. **The database was restored from a dump** taken before a password change. The restored `master` realm has the password as of the dump, not the one in the Secret.
3. **The database was recreated empty.** Keycloak then bootstraps again from the Secret, so the 1Password item is right again (and everything else is gone; [restore](keycloak-backup-restore.md#restore) the dump).
4. **Nobody can sign in to `master` any more.** Keycloak's documented way is the command `kc.sh bootstrap-admin user` with **all Keycloak nodes stopped**, run with the same database options as the server; it creates a new temporary admin in the `master` realm. The Keycloak documentation does not describe this for the Operator, and it has **not been tried here**. The outline: scale down the Keycloak Operator and the `keycloak` StatefulSet, run a one-off pod from the same image, database settings and (new) credentials, delete it, scale up again, then [rotate](#rotate-the-credential) to a known password. Rehearse in `dev` before relying on it.

## Rotate the credential

1. Sign in to the `master` console, open *Users* → `<username>` → *Credentials* → *Reset password* (temporary off) and set the new password.
2. Put the same password into the 1Password item `keycloak-bootstrap-admin#<env>`.
3. Let External Secrets pick it up (within the hour), or force it:

   ```sh
   kubectl annotate externalsecret keycloak-bootstrap-admin -n keycloak --context admin@<env>-homelab force-sync="$(date +%s)" --overwrite
   ```

4. Check that the Terragrunt provider still logs in with it: `terragrunt plan` in `keycloak-automation` of that environment must succeed without drift. `keycloak-realm` does not use this credential ([apply and verify](keycloak-realms.md#apply-and-verify)).

The running pod keeps the old value in its environment until it restarts; that is harmless, as the variables are not read again.

## Verified and not verified

Checked on `qa` (2026-10-26) against the live resources unless noted otherwise:

| Statement | State |
| --- | --- |
| The Secret `keycloak-bootstrap-admin` has the keys `username`, `password`, `notesPlain`; the ExternalSecret is `SecretSynced` | Verified |
| The pod gets `KC_BOOTSTRAP_ADMIN_USERNAME` and `KC_BOOTSTRAP_ADMIN_PASSWORD` from that Secret | Verified |
| `/admin/master/console/` answers (HTTP 200) on `keycloak-service:8080`; the discovery document of `master` takes its host from `hostname` | Verified through a port-forward |
| The operator field is "used only for initial cluster creation" | Verified in the CRD of the Keycloak Operator 26.8.1 |
| `kc.sh bootstrap-admin user` needs all nodes stopped | From the Keycloak documentation, not tried |
| Reading the item with `op item get` | Command standard, not run in this session |
| Sign-in to `master` with the item's credential, the rotation steps, the `kcadm.sh` login | Not tried (no credential read in the writing session) |
| The account still signs in to `master` once the automation client exists, and `keycloak-automation` leaves it unchanged | Verified in `dev` (2026-11-01): the unit, which logs in with this account (password grant), planned, applied and planned again clean after the client existed. The sign-in in the admin console was not tried |
| Facts for `prod` and `rebuild` | Not applicable yet, nothing is deployed there |

## Open points

- **MFA for the bootstrap admin.** The plan asks for the local admin of each core service to have its own MFA where the product supports it. That is not configured on the `master` account here. Enabling it needs a decision first: the Terragrunt provider signs in with the password through the `admin-cli` client and probably cannot answer a one-time-code prompt, so it would need a service account of its own beforehand.
- **A second named `master` admin** per person (instead of only the shared bootstrap account) would make cause 1 above recoverable without the `kc.sh` route. Not decided.
- **Keycloak marks bootstrap accounts as temporary** and recommends removing them after a permanent admin exists. Here the account is kept on purpose, as the break-glass login and the login of the `keycloak-automation` unit; the console may keep warning about it.
- **Rehearse the lost-admin recovery (cause 4)** in `dev`, and the sign-in itself in `prod` once it is deployed ([#1826](https://github.com/isejalabs/homelab/issues/1826)).
