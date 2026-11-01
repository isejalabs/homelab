# Keycloak

[Keycloak](https://www.keycloak.org/) is the identity provider for web single sign-on: users sign in with their UCS accounts and apps trust the tokens it issues. One replica, with its own [CloudNativePG](../../../infra/cnpg-system/cloudnative-pg/README.md) database.

## At a glance

| | |
| --- | --- |
| Namespace | `keycloak` |
| Runs in | `dev`, `qa`, `rebuild` (Flux set `soaking`); not yet in `prod` |
| Installed via | Custom resources `Keycloak` and `Cluster` (CloudNativePG), an `HTTPRoute`, a `CronJob` for the database dump; the servers are created by the [Keycloak operator](../../../infra/keycloak/keycloak-operator/README.md) and the [CloudNativePG operator](../../../infra/cnpg-system/cloudnative-pg/README.md) |
| Flux Kustomization | `keycloak`, depends on `cloudnative-pg`, `gateway-api`, `keycloak-operator`, `longhorn` |

## Purpose

One place that knows who may sign in to what. UCS stays the authoritative directory (Keycloak federates it read-only over LDAPS), Keycloak adds OIDC/SAML for the apps, MFA and separate everyday and admin accounts. Why Keycloak and why in the cluster: [ADR 0016](../../../../docs/decisions/0016-identity-and-web-sso.md); tracking issue [#1826](https://github.com/isejalabs/homelab/issues/1826).

## Where it is used

- **Used by**: the Terragrunt unit `keycloak-realm` (`dev`, `qa`) logs in with the bootstrap admin and manages the realms `iseja` (everyday accounts) and `admin` (`*-adm` accounts), see [`keycloak-realms.md`](../../../../docs/identity/keycloak-realms.md). No application is an OIDC client yet; the clients come with [#1827](https://github.com/isejalabs/homelab/issues/1827) and the per-service integrations.
- **Depends on**:
  - the `keycloak-db` PostgreSQL cluster in the same namespace (CloudNativePG, volume on `longhorn-ha`);
  - the `internal` Gateway in `gateway-api` (TLS ends there, Keycloak speaks plain HTTP on 8080);
  - the UCS domain controllers on LDAPS `7636` and the UCS CA, mounted from the Secret `keycloak-ucs-ca`;
  - External Secrets and 1Password for the bootstrap admin, the database dump credentials and the CA;
  - RustFS on `fiona` (the S3-compatible NAS) for the daily dump, bucket `<env>-keycloak-db`.

## Access

The subdomain is `auth`, not `keycloak`. The general scheme is in [`reference/environments.md`](../../../../docs/reference/environments.md#domain-and-naming).

| env | Base URL | Admin console of the `master` realm |
| --- | --- | --- |
| `dev` | [https://dev-auth.dev.iseja.net](https://dev-auth.dev.iseja.net) | [https://dev-auth.dev.iseja.net/admin/master/console/](https://dev-auth.dev.iseja.net/admin/master/console/) |
| `qa` | [https://qa-auth.qa.iseja.net](https://qa-auth.qa.iseja.net) | [https://qa-auth.qa.iseja.net/admin/master/console/](https://qa-auth.qa.iseja.net/admin/master/console/) |
| `rebuild` | [https://rebuild-auth.rebuild.iseja.net](https://rebuild-auth.rebuild.iseja.net) | [https://rebuild-auth.rebuild.iseja.net/admin/master/console/](https://rebuild-auth.rebuild.iseja.net/admin/master/console/) |
| `prod` | [https://auth.iseja.net](https://auth.iseja.net) (not deployed yet) | [https://auth.iseja.net/admin/master/console/](https://auth.iseja.net/admin/master/console/) |
| `dbg`, `head`, `poc`, `src` | not deployed: Keycloak runs only in the standing environments ([ADR 0016](../../../../docs/decisions/0016-identity-and-web-sso.md), point 2) | |

- **Prod is the exception to the scheme**: it does not get the environment prefix and, unlike every other app, is not under `prod.iseja.net`. The hostname is overridden in [`envs/prod`](envs/prod/kustomization.yaml) for both the `Keycloak` resource and the `HTTPRoute`; the Terragrunt `keycloak_url` must equal it (checked by `kustomize-build`).
- **Reachability**: the `HTTPRoute` is attached to the `internal` Gateway only (LB address `10.8.<env-id>.80`, e.g. `10.8.3.80` in `dev`), so it answers from the LAN, not from the internet. What that exposes: [`keycloak-exposure.md`](../../../../docs/identity/keycloak-exposure.md).
- **Login**: the `master` realm has a local bootstrap admin; username and password are in 1Password, vault `K8S`, item `keycloak-bootstrap-admin#<env>`. The realms `iseja` and `admin` sign in through UCS. When UCS or a realm is down: [`keycloak-break-glass.md`](../../../../docs/identity/keycloak-break-glass.md).

## Updates

- **Keycloak version**: the `Keycloak` resource sets no `spec.image`, so the version is the one the operator ships. It follows the release of the [Keycloak operator](../../../infra/keycloak/keycloak-operator/README.md) (vendored under its `base/vendor/`).
- **PostgreSQL version**: pinned with tag and digest in `spec.imageName` of [`base/cluster.yaml`](base/cluster.yaml); a kustomize replacement copies it into the dump job. Every update is a manual PR, a major one runs `pg_upgrade`: [Upgrading PostgreSQL](../../../../docs/identity/keycloak-backup-restore.md#upgrading-postgresql).
- **Per environment**: `dev`, `qa` and `rebuild` follow `base/`. Once the unit is promoted, `prod` pins its own versions under `envs/prod/` and takes an update only after a 7-day age gate and a manual merge: [Staged rollout: Keycloak and CloudNativePG](../../../../docs/operations/update-handling.md#staged-rollout-keycloak-and-cloudnativepg). Until then `envs/prod/` only carries the hostname, dump bucket and 1Password key overrides.

## Operations

| Task | Doc |
| --- | --- |
| Sign in when UCS or a realm is down; rotate the admin credential | [`keycloak-break-glass.md`](../../../../docs/identity/keycloak-break-glass.md) |
| Back up, restore and drill the database; upgrade PostgreSQL | [`keycloak-backup-restore.md`](../../../../docs/identity/keycloak-backup-restore.md) |
| Realms, LDAP federation, UCS groups (Terragrunt) | [`keycloak-realms.md`](../../../../docs/identity/keycloak-realms.md) |
| What can reach Keycloak, trusted proxy headers, network policy | [`keycloak-exposure.md`](../../../../docs/identity/keycloak-exposure.md) |
| Flux unit stuck or failing | [`troubleshooting-flux.md`](../../../../docs/troubleshooting/troubleshooting-flux.md) |

## Cheat sheet

Replace `<env>` with `dev`, `qa` or `rebuild`. A cold start takes up to about 15 minutes (image pull, `initdb`, Keycloak's first start), so `Ready` can lag; the Flux Kustomization has a 20-minute timeout for that reason.

```sh
# state of the three Flux units and of the workload
flux get ks cloudnative-pg keycloak-operator keycloak --context admin@<env>-homelab
kubectl get keycloak,cluster,httproute,externalsecret -n keycloak --context admin@<env>-homelab
kubectl get pods -n keycloak --context admin@<env>-homelab

# logs (the pod is keycloak-0; the database primary is keycloak-db-1)
kubectl logs -n keycloak keycloak-0 -f --context admin@<env>-homelab
kubectl logs -n keycloak keycloak-db-1 --context admin@<env>-homelab

# is the issuer what it should be? (must equal the hostname in the table above)
curl -s https://<hostname>/realms/master/.well-known/openid-configuration | jq -r .issuer

# bootstrap admin from 1Password (revealed on screen only)
op item get 'keycloak-bootstrap-admin#<env>' --vault K8S --fields label=username,label=password --reveal

# database dumps: list, take one now, restore (see keycloak-backup-restore.md before restoring)
just backup::keycloak::list -e <env>
kubectl create job --from=cronjob/keycloak-db-dump manual-$(date +%Y%m%d-%H%M) -n keycloak --context admin@<env>-homelab
just backup::keycloak::restore -e <env>

# reach the pod without the Gateway (API and discovery only; the console does not work this way)
kubectl port-forward -n keycloak svc/keycloak-service 18080:8080 --context admin@<env>-homelab

# force a reconcile
flux reconcile ks keycloak --with-source --context admin@<env>-homelab
```

## Upstream

- Homepage and docs: <https://www.keycloak.org/>, operator guide <https://www.keycloak.org/operator/installation>, reverse proxy guide <https://www.keycloak.org/server/reverseproxy>
- Source: <https://github.com/keycloak/keycloak>, operator manifests <https://github.com/keycloak/keycloak-k8s-resources>
- Releases: <https://github.com/keycloak/keycloak/releases>
