# Healthchecks

[Healthchecks](https://healthchecks.io/) is a dead-man's-switch monitor: jobs and hosts ping a URL after every run, and an alert goes out when a ping is late. The cluster hosts its own instance because the hosted free tier stops at 10 checks.

## At a glance

| | |
| --- | --- |
| Namespace | `healthchecks` |
| Runs in | `dev` (no Flux set, registered in `k8s/bootstrap/cluster/flux/envs/<env>/kustomization.yaml`); `qa` and `prod` follow |
| Installed via | raw manifests (Deployment, Service, HTTPRoute, ExternalSecret, `CiliumNetworkPolicy`) plus the components `apps/oauth2-proxy` and `apps/storage/pvc` (1Gi, backed up by kopiur) |
| Flux Kustomization | `healthchecks`, depends on `gateway-api`, `longhorn` |

## Purpose

The monitored things in this repository and its siblings (the Keycloak dump heartbeat, the Checkmk site heartbeats of [salt-iseja.net#43](https://github.com/sebiklamar/salt-iseja.net/pull/43), backup freshness) need more checks than the hosted service allows for free. The official image `healthchecks/healthchecks` runs the web UI, `sendalerts` and `sendreports` in one container, with the database in a SQLite file on the volume ([#2275](https://github.com/isejalabs/homelab/issues/2275)).

A heartbeat monitor inside a cluster cannot report that cluster being down. Keep the checks that must survive an outage of the cluster (the Checkmk sites, the Proxmox hosts) on a service outside it.

## Where it is used

- **Used by**: scripts and jobs that ping `/ping/<uuid>`, and people in the web UI.
- **Depends on**: the `internal` Gateway, Longhorn for the volume (and kopiur for its backup), the Keycloak of the environment for the login, and the 1Password items `healthchecks#<env>`, `keycloak-oidc-healthchecks-admin#<env>` and `oauth2-proxy-healthchecks#<env>` (External Secrets).

## Access

Through the `internal` Gateway, always via the OAuth2 Proxy of the unit: only members of the UCS group `sec.app.healthchecks.admin` (realm `admin`) can sign in, and the first sign-in creates the account. `/ping/` is the one path that needs no login, so a monitored host can ping with just the URL.

| env | URL |
| --- | --- |
| `dev` | [https://dev-healthchecks.dev.iseja.net](https://dev-healthchecks.dev.iseja.net) |

The application trusts the header `X-Forwarded-Email` of the proxy (`REMOTE_USER_HEADER`) and has self-registration off. That is why the `CiliumNetworkPolicy` admits only the proxy to the pod and why the route never points at the Service `healthchecks` directly: a client that could reach the pod would be signed in as whoever it names. The proxy puts the login name of the Keycloak account in that header, not an e-mail address, so the account's own e-mail integration is not usable; add an e-mail address integration by hand.

## Updates

The image is pinned (tag and digest) in [`base/deployment.yaml`](base/deployment.yaml); Renovate bumps both. The proxy's chart is pinned once for every consumer in the [component](../../../components/apps/oauth2-proxy/README.md#updates). No special Renovate rule: default flow of [`update-handling.md`](../../../../docs/operations/update-handling.md). The container runs the database migrations on every start.

## Operations

| Task | Doc |
| --- | --- |
| Back up, restore, or import data into a blank PVC | [`kopiur-backup-restore.md`](../../../../docs/backup/kopiur-backup-restore.md) |
| How the login proxy works, reuse it | [`oauth2-proxy.md`](../../../../docs/identity/oauth2-proxy.md) |

## Cheat sheet

```sh
flux get ks healthchecks --context admin@<env>-homelab
kubectl get pods,pvc,httproute,externalsecret -n healthchecks --context admin@<env>-homelab
kubectl logs -n healthchecks deploy/healthchecks -f --context admin@<env>-homelab

# break-glass: the UI without Keycloak (the application then sees no REMOTE_USER_HEADER and shows its own login page,
# which only works for an account with a password; create one with the command below), then open http://localhost:8000
kubectl port-forward -n healthchecks svc/healthchecks 8000:8000 --context admin@<env>-homelab
kubectl exec -n healthchecks deploy/healthchecks --context admin@<env>-homelab -it -- ./manage.py createsuperuser

# ping a check (no login needed)
curl -fsS https://<host>/ping/<uuid>
```

## Upstream

- Homepage and documentation: <https://healthchecks.io/>, <https://healthchecks.io/docs/self_hosted/>, <https://healthchecks.io/docs/self_hosted_configuration/>
- Source and releases: <https://github.com/healthchecks/healthchecks>
- Image: <https://hub.docker.com/r/healthchecks/healthchecks>
