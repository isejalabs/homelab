# 1Password Connect

The [1Password Connect](https://developer.1password.com/docs/connect/) server gives the cluster API access to one 1Password vault (`K8S`). The `ClusterSecretStore` `onepassword-connect` points the [External Secrets Operator](../external-secrets/README.md) at it.

## At a glance

| | |
| --- | --- |
| Namespace | `external-secrets` (shared with the operator) |
| Runs in | all 8 environments (Flux set `minimal`); installed by the bootstrap helmfile after `external-secrets`, then taken over by Flux |
| Installed via | HelmRelease, chart from the OCI repository `ghcr.io/1password/connect` ([`base/ocirepository.yaml`](base/ocirepository.yaml)), plus the `ClusterSecretStore` and two `ExternalSecret`s |
| Flux Kustomization | `onepassword-connect`, depends on `external-secrets` |

## Purpose

The bridge to 1Password, the source of truth for every in-cluster secret that is not sealed. It is a chicken-and-egg component: ESO needs it to fetch secrets, and it needs two secrets itself, so those are injected during the bootstrap and only then managed by ESO.

## Where it is used

- **Used by**: the External Secrets Operator, through the `ClusterSecretStore` (vault `K8S`, host `http://onepassword-connect.external-secrets.svc.cluster.local`), and so by every `ExternalSecret` in the cluster.
- **Depends on**: the Secrets `onepassword-connect-credentials-secret` (the Connect server's credentials file) and `onepassword-connect-vault-secret` (the API token). `just bootstrap::cluster` creates them with `op inject` from [`k8s/bootstrap/kustomize/personal/external-secrets/`](../../../bootstrap/kustomize/personal/external-secrets/s3cr3t.yaml); afterwards the two `ExternalSecret`s here take them over from the 1Password item `1password`. Bootstrap walkthrough: [`k8s/bootstrap/README.md`](../../../bootstrap/README.md).

## Access

Not exposed. In-cluster only, on the Service `onepassword-connect` in `external-secrets`. The server reaches out to 1Password; no inbound access is needed.

## Updates

- **Chart**: tag and digest in [`base/ocirepository.yaml`](base/ocirepository.yaml). No special Renovate rule: the default flow of [`update-handling.md`](../../../../docs/operations/update-handling.md) applies.

## Operations

| Task | Doc |
| --- | --- |
| Overall secrets story | [`secrets.md`](../../../../docs/architecture/secrets.md) |
| Rebuild a cluster (new Connect credentials may be needed) | [`disaster-recovery.md`](../../../../docs/backup/disaster-recovery.md) |

## Cheat sheet

Replace `<env>` with the environment.

```sh
flux get ks onepassword-connect --context admin@<env>-homelab
kubectl get pods,svc -n external-secrets --context admin@<env>-homelab

# the store and the two ExternalSecrets of the Connect server itself
kubectl get clustersecretstore --context admin@<env>-homelab
kubectl get externalsecrets.external-secrets.io -n external-secrets --context admin@<env>-homelab
# expected: onepassword-connect-credentials and onepassword-connect-token, STATUS SecretSynced, READY True

# read an item from the vault with the CLI
op item get 'keycloak-bootstrap-admin#dev' --vault K8S
```

## Upstream

- Documentation: <https://developer.1password.com/docs/connect/>, <https://www.1password.dev/connect/get-started?method=1password-cli#1password-cli>
- Chart and source: <https://github.com/1Password/connect-helm-charts>
- Background: <https://rcwz.pl/2025-10-13-managing-secrets-with-1password-and-external-secrets/>, [onedr0p's implementation](https://github.com/onedr0p/home-ops/tree/7ea61fe39704cc339c8b29f4375f207ef8ea9d15/kubernetes/apps/external-secrets)

## Create the connection parameters with the `op` CLI (kept from the earlier README)

One-time setup of the Connect server and its token, before the first bootstrap. The credentials file and the token go to the 1Password item `1password` (fields `OP_SESSION_JSON`, `OP_CONNECT_TOKEN`), from where `op inject` reads them.

```sh
# op connect server create
$ op connect server create k8s --vaults K8S
Set up a Connect server.
UUID: C4SMSGSK2JEW5KCB2UPP4VGP7Q
Credentials file: /Users/sebi/src/homelab/1password-credentials.json

# op connect token create
$ op connect token create k8s --server k8s --vault K8S
```
