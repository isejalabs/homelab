# Sealed Secrets

The [Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) controller decrypts `SealedSecret` objects into ordinary `Secret`s, so an encrypted secret can live in Git and only the cluster can read it.

## At a glance

| | |
| --- | --- |
| Namespace | `sealed-secrets` |
| Runs in | all 8 environments (Flux set `minimal`); installed by the bootstrap helmfile right after `cilium`, then taken over by Flux |
| Installed via | HelmRelease with the Bitnami OCI chart `oci://registry-1.docker.io/bitnamicharts/sealed-secrets` |
| Flux Kustomization | `sealed-secrets`, depends on `infra-ns` |

## Purpose

The first secrets mechanism of the cluster: it works before External Secrets and 1Password exist, so the secrets needed to get those running (and a few that stay, such as the AdGuard users, the UniFi MongoDB credentials and the Cloudflare API token) are sealed. Everything else comes from 1Password through External Secrets. Which mechanism is for what, and why: [`secrets.md`](../../../../docs/architecture/secrets.md), [ADR 0010](../../../../docs/decisions/0010-sops-vs-sealed-secrets-vs-1password-eso.md).

## Where it is used

- **Used by**: units with a `SealedSecret`: `adguard` (`users`), `unifi-mongodb` (`db-secret-sealed`), `cert-manager` (`cloudflare-api-token`), and every unit that `dependsOn` `sealed-secrets` for this reason.
- **Depends on**: its key pair. Terragrunt provisions it (module `bootstrap/sealed-secrets`) as the TLS secret `sealed-secrets-bootstrap-key` from `assets/sealed-secrets/certificate/sealed-secrets.{cert,key}` next to each environment's `vehagn-k8s` unit. Those two files are gitignored and exist only in the checkout that generated them. Never generate a new pair: a different key breaks every existing `SealedSecret` ([`terragrunt/README.md`](../../../../terragrunt/README.md#sealed-secrets-key-files-in-a-fresh-checkout)).

## Access

Not exposed. `kubeseal` talks to the controller `sealed-secrets` in the namespace `sealed-secrets` (`--controller-name`/`--controller-namespace`), or works offline with the environment's public certificate `terragrunt/<tier>/eu-central-1/<env>/vehagn-k8s/assets/sealed-secrets/certificate/sealed-secrets.cert` (gitignored, so it is only in the checkout that generated it).

## Updates

- **Chart**: tag in [`base/ocirepository.yaml`](base/ocirepository.yaml). No special Renovate rule: the default flow of [`update-handling.md`](../../../../docs/operations/update-handling.md) applies. Because the chart is installed by the bootstrap helmfile first, the same version is used there.

## Operations

| Task | Doc |
| --- | --- |
| Plan or apply in a fresh checkout without the key files | [`terragrunt/README.md`](../../../../terragrunt/README.md#sealed-secrets-key-files-in-a-fresh-checkout), [`k8s-minor-upgrade.md`](../../../../docs/operations/k8s-minor-upgrade.md) |
| Overall secrets story | [`secrets.md`](../../../../docs/architecture/secrets.md) |

## Cheat sheet

You need the `kubeseal` CLI. Replace `<env>` with the environment. Leading blank spaces in the commands below keep them out of the shell history.

```sh
flux get ks sealed-secrets --context admin@<env>-homelab
kubectl get sealedsecrets.bitnami.com -A --context admin@<env>-homelab

# check that the controller works: seal a throwaway value
echo -n mytestsecret | kubectl create secret generic mysecretname --dry-run=client --from-file=mykey=/dev/stdin -o yaml | kubeseal --controller-namespace sealed-secrets -o yaml -n mynamespace

# seal a value into an existing SealedSecret file (adguard's users, as an example)
cat users.yaml | kubectl create secret generic users --dry-run=client --from-file=users.yaml=/dev/stdin -o yaml | kubeseal --cert terragrunt/non-prod/eu-central-1/dev/vehagn-k8s/assets/sealed-secrets/certificate/sealed-secrets.cert -o yaml -n adguard --merge-into k8s/apps/dns/adguard/base/secret-users.yaml
```

A `SealedSecret` is bound to name and namespace: seal it for the namespace the `Secret` ends up in.

## Upstream

- Source and releases: <https://github.com/bitnami-labs/sealed-secrets>
- Documentation: <https://github.com/bitnami-labs/sealed-secrets#readme>

## Decrypt and recovery (kept from the earlier README)

Back up the sealing key (it decrypts every sealed secret of the cluster, so store it like a password):

```sh
kubectl get secrets -n sealed-secrets -o yaml > sealed-secrets-key.yaml
```

Test a sealed secret against that key without a cluster. The file names and paths are the ones of the earlier repository layout (`infra/controllers/...`); use the path of the `SealedSecret` you want to check:

```sh
kubeseal --controller-name=sealed-secrets --controller-namespace=sealed-secrets < <path-to-sealedsecret.yaml> --recovery-unseal --recovery-private-key sealed-secrets-key.yaml -o json | jq -r '.data."<key>" | @base64d'
```

Seal into a file with `--merge-into`: the same command as in the cheat sheet, with the target file's namespace for `-n`. The earlier README also listed commands for secrets that no longer exist in this repository (`cloudflared`'s tunnel credentials, with `infra/network/...` paths); they were removed because their paths do not exist any more.
