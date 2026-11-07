# CloudNativePG

[CloudNativePG](https://cloudnative-pg.io/) is the PostgreSQL operator: a `Cluster` custom resource becomes a running PostgreSQL (pods, volumes, services, credentials).

## At a glance

| | |
| --- | --- |
| Namespace | `cnpg-system` (namespace manifest in [`../_ns/`](../_ns/base/ns.yaml)) |
| Runs in | `dev`, `qa`, `rebuild` (Flux set `soaking`); not yet in `prod` |
| Installed via | HelmRelease, chart from the OCI repository `ghcr.io/cloudnative-pg/charts/cloudnative-pg` ([`base/ocirepository.yaml`](base/ocirepository.yaml)); CRDs come with the chart (`crds.create: true`) |
| Flux Kustomization | `cloudnative-pg`, depends on `infra-ns` |

## Purpose

Runs the database of workloads that need PostgreSQL. It was introduced for Keycloak ([#1826](https://github.com/isejalabs/homelab/issues/1826)); the operator is generic, so a later app that needs PostgreSQL adds its own `Cluster` and does not need a new operator. Metrics are off (`monitoring.podMonitorEnabled: false`, no Grafana dashboard) because there is no Prometheus stack in the cluster.

## Where it is used

- **Used by**: one `Cluster`, `keycloak-db` in namespace `keycloak` ([`apps/identity/keycloak`](../../../apps/identity/keycloak/README.md)): one instance, 1 Gi on `longhorn-ha`, no WAL archiving; backed up by a daily `pg_dump` instead of CloudNativePG backups. Find all clusters with the first command in the [cheat sheet](#cheat-sheet).
- **Depends on**: nothing at runtime beyond the API server. The volumes of the databases it manages come from [Longhorn](../../longhorn-system/longhorn-core/base/) in the clusters that use it ([`storage.md`](../../../../docs/architecture/storage.md)).

## Access

Not exposed. The operator has no UI. Each database is reachable in-cluster only, through the services CloudNativePG creates per `Cluster` (`<cluster>-rw` for the primary, e.g. `keycloak-db-rw.keycloak`).

## Updates

- **Operator**: chart tag and digest in [`base/ocirepository.yaml`](base/ocirepository.yaml) (`spec.ref`). `dev`, `qa` and `rebuild` follow `base/` through the normal Renovate flow ([`update-handling.md`](../../../../docs/operations/update-handling.md#how-a-renovate-pull-request-gets-merged)).
- **Once promoted to `prod`**: `prod` pins the chart itself under `envs/prod/` (like [cilium's](../../kube-system/cilium/envs/prod/ocirepository.yaml)) and takes an update only after a 7-day age gate and a manual merge: [Staged rollout: Keycloak and CloudNativePG](../../../../docs/operations/update-handling.md#staged-rollout-keycloak-and-cloudnativepg). Until then the pin file does not exist.
- **PostgreSQL images** are not set here but in each `Cluster` (`spec.imageName`), pinned on purpose so an operator bump never changes the database version. They are manual PRs: see the `ghcr.io/cloudnative-pg/postgresql` row in [Non-standard update strategies](../../../../docs/operations/update-handling.md#non-standard-update-strategies) and [Upgrading PostgreSQL](../../../../docs/identity/keycloak-backup-restore.md#upgrading-postgresql).

## Operations

| Task | Doc |
| --- | --- |
| Back up, restore and upgrade the Keycloak database | [`keycloak-backup-restore.md`](../../../../docs/identity/keycloak-backup-restore.md) |
| Flux unit stuck or failing | [`troubleshooting-flux.md`](../../../../docs/troubleshooting/troubleshooting-flux.md) |
| PVC or Longhorn volume problems | [`troubleshooting-storage.md`](../../../../docs/troubleshooting/troubleshooting-storage.md) |

## Cheat sheet

Replace `<env>` with `dev`, `qa` or `rebuild`.

```sh
# every database cluster managed by the operator, and the operator itself
kubectl get clusters.postgresql.cnpg.io -A --context admin@<env>-homelab
kubectl get deploy,pods -n cnpg-system --context admin@<env>-homelab

# why is a cluster not Ready?
kubectl describe clusters.postgresql.cnpg.io keycloak-db -n keycloak --context admin@<env>-homelab
kubectl logs -n cnpg-system deploy/cloudnative-pg --context admin@<env>-homelab

# the primary's logs and a psql shell (the app user and database are both keycloak)
kubectl logs -n keycloak keycloak-db-1 --context admin@<env>-homelab
kubectl exec -it -n keycloak keycloak-db-1 --context admin@<env>-homelab -- psql -U postgres -d keycloak

flux get ks cloudnative-pg --context admin@<env>-homelab
```

## Upstream

- Homepage and documentation: <https://cloudnative-pg.io/documentation/current/>
- Source and releases: <https://github.com/cloudnative-pg/cloudnative-pg>
- Chart: <https://github.com/cloudnative-pg/charts>
