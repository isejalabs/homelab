# Keycloak operator

The [Keycloak Operator](https://www.keycloak.org/operator/installation) turns a `Keycloak` custom resource into a running Keycloak (StatefulSet, Services, probes, truststores). It is also what decides which Keycloak version runs.

## At a glance

| | |
| --- | --- |
| Namespace | `keycloak` (namespace manifest in [`../_ns/`](../_ns/base/ns.yaml)) |
| Runs in | `dev`, `qa`, `rebuild` (Flux set `soaking`); not yet in `prod` |
| Installed via | Upstream release manifests, vendored under [`base/vendor/`](base/vendor/) (CRDs and the operator `Deployment`), with one probe patch |
| Flux Kustomization | `keycloak-operator`, depends on `infra-ns` |

## Purpose

Upstream publishes the operator as plain manifests, not as a Helm chart, and Flux must not fetch them from the internet at build time, so the release is vendored (see [`kustomize.md`](../../../../docs/architecture/kustomize.md#vendored-upstream-manifests)). Why Keycloak runs in the cluster at all: [ADR 0016](../../../../docs/decisions/0016-identity-and-web-sso.md).

## Where it is used

- **Used by**: [`apps/identity/keycloak`](../../../apps/identity/keycloak/README.md), the only `Keycloak` resource. The CRDs for `KeycloakRealmImport`, `KeycloakOIDCClient` and `KeycloakSAMLClient` are installed too but nothing uses them; realms are managed by the Terragrunt unit `keycloak-realm` ([`keycloak-realms.md`](../../../../docs/identity/keycloak-realms.md)).
- **Depends on**: nothing at runtime beyond the API server. The `keycloak` unit depends on this one.

## Access

Not exposed. The operator has no UI; it talks to the API server only.

## Updates

- **Version**: the release number is in the upstream URL comments of [`base/kustomization.yaml`](base/kustomization.yaml) (`keycloak-k8s-resources/<version>/...`), next to the files under `base/vendor/`. The operator version also selects the Keycloak server version, since the `Keycloak` resource sets no image.
- **Flow**: Renovate bumps the URLs; run `scripts/vendor-manifests.sh update` on that PR branch to fetch the matching files (the `kustomize-build` check fails until they match). Details: [`update-handling.md`](../../../../docs/operations/update-handling.md#renovate).
- **Per environment**: `dev`, `qa` and `rebuild` follow `base/`. Once promoted, `prod` needs its own pin, which is an open point because an overlay cannot patch vendored files: [Staged rollout: Keycloak and CloudNativePG](../../../../docs/operations/update-handling.md#staged-rollout-keycloak-and-cloudnativepg).
- **After every bump**: re-check the startup probe patch in `base/kustomization.yaml` (upstream's own probe kills the operator, which needs about 26 s to start).

## Operations

Nothing specific. Flux problems: [`troubleshooting-flux.md`](../../../../docs/troubleshooting/troubleshooting-flux.md).

## Cheat sheet

```sh
flux get ks keycloak-operator --context admin@<env>-homelab
kubectl get deploy,pods -n keycloak --context admin@<env>-homelab
kubectl logs -n keycloak deploy/keycloak-operator --context admin@<env>-homelab

# fetch the vendored files for the version in the URL comments, then check
scripts/vendor-manifests.sh update
scripts/vendor-manifests.sh check
```

## Upstream

- Documentation: <https://www.keycloak.org/operator/installation>
- Manifests per release: <https://github.com/keycloak/keycloak-k8s-resources>
- Source and releases: <https://github.com/keycloak/keycloak>
