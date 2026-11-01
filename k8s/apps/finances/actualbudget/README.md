# Actual Budget

[Actual Budget](https://actualbudget.org/) is a self-hosted personal finance and budgeting app.

## At a glance

| | |
| --- | --- |
| Namespace | `actualbudget` |
| Runs in | `head`, `prod`, `qa`, `rebuild` (Flux set `optional`) |
| Installed via | HelmRelease, chart `actualbudget` from the `community-charts` Helm repository, plus the `apps/storage/pvc` component (1Gi, backed up by kopiur) |
| Flux Kustomization | `actualbudget`, depends on `gateway-api`, `longhorn` |

## Purpose

The household budget. The data (budget files and the server database) is in one PVC, so a backup of that volume is a backup of the app.

## Where it is used

- **Used by**: people, through the browser. Nothing else in the cluster depends on it.
- **Depends on**: the `internal` Gateway for access, and Longhorn for the volume (and kopiur for its backup).

## Access

Through the `internal` Gateway; the subdomain is `budget`, not `actualbudget`. The general scheme is in [`reference/environments.md`](../../../../docs/reference/environments.md#domain-and-naming).

| env | URL |
| --- | --- |
| `head` | [https://head-budget.head.iseja.net](https://head-budget.head.iseja.net) |
| `qa` | [https://qa-budget.qa.iseja.net](https://qa-budget.qa.iseja.net) |
| `rebuild` | [https://rebuild-budget.rebuild.iseja.net](https://rebuild-budget.rebuild.iseja.net) |
| `prod` | [https://budget.prod.iseja.net](https://budget.prod.iseja.net) |

The server password is set in the app on first start; there is no credential in Git.

## Updates

- **Chart**: `spec.chart.spec.version` in [`base/helmrelease.yaml`](base/helmrelease.yaml).
- **Image**: tracked separately in `values.image.tag` of the same file, because the chart version does not always follow the application version (a `renovate: docker=ghcr.io/actualbudget/actual-server` comment drives it).
- No special Renovate rule: default flow of [`update-handling.md`](../../../../docs/operations/update-handling.md).

## Operations

| Task | Doc |
| --- | --- |
| Back up, restore, or import data into a blank PVC | [`kopiur-backup-restore.md`](../../../../docs/backup/kopiur-backup-restore.md) |
| PVC or volume problems | [`troubleshooting-storage.md`](../../../../docs/troubleshooting/troubleshooting-storage.md) |

## Cheat sheet

```sh
flux get ks actualbudget --context admin@<env>-homelab
flux get hr -n actualbudget --context admin@<env>-homelab
kubectl get pods,pvc,httproute -n actualbudget --context admin@<env>-homelab
kubectl logs -n actualbudget deploy/actualbudget -f --context admin@<env>-homelab

# backup now, list snapshots
just backup::kopiur::create actualbudget -e <env> -n actualbudget
just backup::kopiur::list actualbudget -e <env> -n actualbudget
```

## Upstream

- Homepage and documentation: <https://actualbudget.org/>, <https://actualbudget.org/docs/>
- Source and releases: <https://github.com/actualbudget/actual>
- Chart: <https://github.com/community-charts/helm-charts>
