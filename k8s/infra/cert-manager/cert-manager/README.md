# cert-manager

[cert-manager](https://cert-manager.io/) issues and renews TLS certificates. Here it gets a wildcard certificate per environment from Let's Encrypt, proving domain ownership by a DNS-01 challenge through Cloudflare.

## At a glance

| | |
| --- | --- |
| Namespace | `cert-manager` |
| Runs in | all 8 environments (Flux set `minimal`); installed by the bootstrap helmfile after `sealed-secrets`, then taken over by Flux |
| Installed via | HelmRelease, chart from the OCI repository `quay.io/jetstack/charts/cert-manager` ([`base/ocirepository.yaml`](base/ocirepository.yaml)); the `ClusterIssuer` and a SealedSecret for the Cloudflare token are in `base/` |
| Flux Kustomization | `cert-manager`, no `dependsOn` |

## Purpose

HTTPS everywhere without manual certificates: one `Certificate` per Gateway for `*.<env>.iseja.net`, renewed automatically. The Gateway API support is enabled (`config.gatewayAPI.enabled`), the CRDs are part of the release (`crds.enabled`). DNS-01 challenges use external resolvers (`dns01RecursiveNameservers`, Cloudflare and Quad9 over DoH) because the internal DNS is split. See [`network.md`](../../../../docs/architecture/network.md#gateway-api-cilium-as-the-implementation).

## Where it is used

- **Used by**: the [`gateway`](../../gateway-api/gateway/README.md) unit, whose `Certificate` `cert` in namespace `gateway-api` is the only certificate issued today and backs the `internal` and `external` Gateways.
- **Depends on**: the SealedSecret `cloudflare-api-token` (decrypted by [`sealed-secrets`](../../sealed-secrets/sealed-secrets/README.md)), Cloudflare for the DNS-01 TXT records, and Let's Encrypt.

## Access

Not exposed. The issuer is the `ClusterIssuer` `cloudflare-cluster-issuer`.

| env | Let's Encrypt CA |
| --- | --- |
| `dev`, `prod`, `qa`, `rebuild` | production (`acme-v02`), trusted by browsers |
| `dbg`, `head`, `poc`, `src` | staging (`acme-staging-v02`), **not trusted** by browsers |

The base issuer selects staging; the four environments with production override it in `envs/<env>/cluster-issuer.yaml` (which also sets the account email). Rate limits, notably for repeatedly rebuilt `rebuild`: [`network.md`](../../../../docs/architecture/network.md#lets-encrypt-production-limits-and-rebuild).

## Updates

- **Chart**: tag and digest in [`base/ocirepository.yaml`](base/ocirepository.yaml). No special Renovate rule: the default flow of [`update-handling.md`](../../../../docs/operations/update-handling.md) applies. The bootstrap helmfile installs the same chart first.

## Operations

| Task | Doc |
| --- | --- |
| Issuer, staging versus production, rate limits | [`network.md`](../../../../docs/architecture/network.md#gateway-api-cilium-as-the-implementation) |
| Rotate the Cloudflare token | seal the new value into [`base/cloudflare-api-token.yaml`](base/cloudflare-api-token.yaml) with `kubeseal` ([`sealed-secrets`](../../sealed-secrets/sealed-secrets/README.md#cheat-sheet)) |

## Cheat sheet

Replace `<env>` with the environment.

```sh
flux get ks cert-manager --context admin@<env>-homelab
kubectl get pods -n cert-manager --context admin@<env>-homelab

# is the Gateway certificate issued?
kubectl get certificate -n gateway-api --context admin@<env>-homelab
# NAME   READY   SECRET   AGE
# cert   True    cert     1m

# why not? walk the chain: certificate, request, order, challenge
kubectl describe certificate cert -n gateway-api --context admin@<env>-homelab
kubectl get certificaterequest,order,challenge -A --context admin@<env>-homelab

kubectl logs -n cert-manager services/cert-manager -f --context admin@<env>-homelab

# the (decrypted) Cloudflare token, printed to the terminal
kubectl get secrets -n cert-manager cloudflare-api-token -o json --context admin@<env>-homelab | jq -r '.data."api-token" | @base64d'
```

## Upstream

- Homepage and documentation: <https://cert-manager.io/>, <https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/>
- Source and releases: <https://github.com/cert-manager/cert-manager>
