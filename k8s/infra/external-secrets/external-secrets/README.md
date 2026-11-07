# External Secrets Operator

The [External Secrets Operator](https://external-secrets.io/) (ESO) reads secrets from an external store, here a 1Password vault, and writes them as ordinary Kubernetes `Secret`s that stay in step with the source.

## At a glance

| | |
| --- | --- |
| Namespace | `external-secrets` |
| Runs in | all 8 environments (Flux set `minimal`); installed by the bootstrap helmfile after `cilium`, then taken over by Flux |
| Installed via | HelmRelease, chart from the OCI repository `ghcr.io/external-secrets/charts/external-secrets` ([`base/ocirepository.yaml`](base/ocirepository.yaml)), plus a PodDisruptionBudget and a Grafana dashboard |
| Flux Kustomization | `external-secrets`, depends on `infra-ns` |

## Purpose

Keeps secrets out of Git altogether: a manifest names a 1Password item, ESO fetches the fields and keeps the `Secret` current (refresh interval 1 h for most). It is the main secrets mechanism, [sealed-secrets](../../sealed-secrets/sealed-secrets/README.md) being the exception for what must exist first. Which one is for what: [`secrets.md`](../../../../docs/architecture/secrets.md#in-cluster-secrets-sealed-secrets-vs-1password--eso), [ADR 0010](../../../../docs/decisions/0010-sops-vs-sealed-secrets-vs-1password-eso.md).

## Where it is used

- **Used by**: every unit with an `ExternalSecret`, for example `keycloak` (bootstrap admin, dump credentials, UCS CA), `powerdns` and `external-dns` (TSIG keys), `kopiur` (backup repository credentials), `zigbee2mqtt` (MQTT login). Items are named per environment with a `#<env>` suffix where an environment needs its own value.
- **Depends on**: the `ClusterSecretStore` `onepassword-connect` ([`onepassword-connect`](../onepassword-connect/README.md)), which is where it reads from.

## Access

Not exposed.

## Updates

- **Chart**: tag and digest in [`base/ocirepository.yaml`](base/ocirepository.yaml). No special Renovate rule: the default flow of [`update-handling.md`](../../../../docs/operations/update-handling.md) applies. The bootstrap helmfile installs the same chart first.
- The webhook runs with two replicas; leader election timings are relaxed (60 s lease) to write less to etcd.

## Operations

| Task | Doc |
| --- | --- |
| How secrets flow, and which items exist | [`secrets.md`](../../../../docs/architecture/secrets.md) |
| A secret is missing or stale | cheat sheet below |

## Cheat sheet

Replace `<env>` with the environment.

```sh
flux get ks external-secrets onepassword-connect --context admin@<env>-homelab

# every ExternalSecret in the cluster and whether it synced
kubectl get externalsecrets.external-secrets.io -A --context admin@<env>-homelab

# why is one failing? (conditions and events)
kubectl describe externalsecret <name> -n <namespace> --context admin@<env>-homelab

# force a refresh now
kubectl annotate externalsecret <name> -n <namespace> force-sync=$(date +%s) --overwrite --context admin@<env>-homelab
```

## Upstream

- Homepage and documentation: <https://external-secrets.io/>
- Source and releases: <https://github.com/external-secrets/external-secrets>
- 1Password provider: <https://external-secrets.io/latest/provider/1password-automation/>
