# Secrets management

Secrets never live in Git in plaintext. This repo uses two mechanisms, and the split between them is
mechanical, not stylistic: **SOPS** for anything that has to exist *before* a Kubernetes cluster and Flux are
running, and **sealed-secrets** / **1Password + External Secrets Operator (ESO)** for anything a running
cluster reconciles from Git afterwards. A one-time bridge (`op inject`) connects the two during bootstrap.

```
provisioning (SOPS)  --->  bootstrap bridge (op inject)  --->  in-cluster (sealed-secrets / ESO+1Password)
   no cluster yet         cluster exists, Flux doesn't yet        Flux reconciling from Git
```

## SOPS: provisioning secrets

Before any VM, Talos node, or Kubernetes API exists, [Terragrunt](../../terragrunt/) still needs real
credentials (Proxmox API tokens, the remote-state encryption passphrase, ...). There is no cluster yet to run
a controller that could serve those secrets, so this layer has to be static, file-based encryption:
[SOPS](https://github.com/getsops/sops) with a single [age](https://github.com/FiloSottile/age) recipient,
configured in [`.sops.yaml`](../../.sops.yaml):

```yaml
creation_rules:
  # partially (key) encrypted file
  - age: 'age1247uvu7q0r842e78xxk5zt0yz0luh90zvsvzdzxdt6ql8xt76ygszj8eq9'
    path_regex: (kubernetes|talos|clusters)/.*\.sops\.ya?ml
    encrypted_regex: "((?i)(^trusted|^secrets|^trustdinfo|^cluster|.[pP]assword|crt|key|^data$|^stringData))"
  - age: 'age1247uvu7q0r842e78xxk5zt0yz0luh90zvsvzdzxdt6ql8xt76ygszj8eq9'
    path_regex: (tofu|terraform|terragrunt)/.*\.auto\.tfvars(\.json)?
  - age: 'age1247uvu7q0r842e78xxk5zt0yz0luh90zvsvzdzxdt6ql8xt76ygszj8eq9'
    path_regex: .*-secrets\.ya?ml
```

Three rules, one recipient:

- `(kubernetes|talos|clusters)/*.sops.yaml` — **partial** encryption (only values whose *key* matches
  `encrypted_regex` get encrypted; everything else stays plaintext for readability). This targets Talos
  machine-config-style secrets; no file matching this rule exists in the repo yet, so treat it as reserved
  for future use rather than something to go looking for today.
- `(tofu|terraform|terragrunt)/*.auto.tfvars(.json)?` — full encryption for OpenTofu/Terraform auto-loaded
  tfvars. Also currently unused — no `.auto.tfvars` files exist in the repo yet.
- `*-secrets.yaml` (renamed `*-secrets.sops.yaml` once encrypted) — full encryption. This is the one actually
  in use: [`terragrunt/global-secrets.sops.yaml`](../../terragrunt/global-secrets.sops.yaml),
  [`terragrunt/non-prod/account-secrets.sops.yaml`](../../terragrunt/non-prod/account-secrets.sops.yaml), and
  [`terragrunt/prod/account-secrets.sops.yaml`](../../terragrunt/prod/account-secrets.sops.yaml).

SOPS leaves keys and structure in plaintext by design — only values are encrypted — which is what makes a
diff of an encrypted file still reviewable:

```yaml
# terragrunt/global-secrets.sops.yaml (structure; values redacted)
proxmox:
    cluster_name: ENC[AES256_GCM,data:...,type:str]
    endpoint: ENC[AES256_GCM,data:...,type:str]
    insecure: ENC[AES256_GCM,data:...,type:bool]
    username: ENC[AES256_GCM,data:...,type:str]
proxmox_api_token: ENC[AES256_GCM,data:...,type:str]
sops:
    age:
      - recipient: age1247uvu7q0r842e78xxk5zt0yz0luh90zvsvzdzxdt6ql8xt76ygszj8eq9
        enc: |
          -----BEGIN AGE ENCRYPTED FILE-----...
    lastmodified: "..."
    mac: ENC[...]
    version: 3.11.0
```

**Never hand-edit an already-encrypted `*.sops.yaml` file.** Use the two helper scripts instead:
[`scripts/sops-encrypt-all.sh`](../../scripts/sops-encrypt-all.sh) parses the `path_regex:` lines straight out
of `.sops.yaml`, finds every matching plaintext file, diffs it against its already-encrypted counterpart, and
re-encrypts only what changed; [`scripts/sops-decrypt-all.sh`](../../scripts/sops-decrypt-all.sh) does the
reverse (decrypt every `*.sops.yaml` to a sibling plaintext file, only overwriting a stale copy with `-f`).

### How Terragrunt reads them

[`terragrunt/root.hcl`](../../terragrunt/root.hcl) decrypts and merges up to five optional files, each
overriding the one before it — global, then account, then region, then environment, then a component-local
file:

```hcl
# <root>/global-secrets.sops.yaml
# <root>/<account>/account-secrets.sops.yaml
# <root>/<account>/<region>/region-secrets.sops.yaml
# <root>/<account>/<region>/<env>/env-secrets.sops.yaml
# <root>/<account>/<region>/<env>/<component>/local-secrets.sops.yaml

global_secret_vars      = try(yamldecode(sops_decrypt_file(find_in_parent_folders("global-secrets.sops.yaml"))), {})
account_secret_vars     = try(yamldecode(sops_decrypt_file(find_in_parent_folders("account-secrets.sops.yaml"))), {})
region_secret_vars      = try(yamldecode(sops_decrypt_file(find_in_parent_folders("region-secrets.sops.yaml"))), {})
environment_secret_vars = try(yamldecode(sops_decrypt_file(find_in_parent_folders("env-secrets.sops.yaml"))), {})
local_secret_vars       = try(yamldecode(sops_decrypt_file("local-secrets.sops.yaml")), {})

secret_vars = merge(
  local.global_secret_vars,
  local.account_secret_vars,
  local.region_secret_vars,
  local.environment_secret_vars,
  local.local_secret_vars,
)
```

Every file is optional (`try(...)` defaults to `{}`), and a child module never gets secrets injected
automatically — it opts in explicitly via `include.root.locals.secret_vars.<name>`. One value out of this
merged map is itself load-bearing for the whole pipeline: `secret_vars.state_encryption_passphrase` is what
Terragrunt uses to encrypt the S3 remote-state backend (see
[`docs/architecture/terraform-bootstrap.md`](terraform-bootstrap.md)) — so the very first `terragrunt`
command a fresh checkout runs already depends on a SOPS-decrypted value.

## The bootstrap bridge: `op inject`

Once Talos/Kubernetes is up but before Flux exists, [`k8s/bootstrap/`](../../k8s/bootstrap/README.md) still
needs to seed one thing into the cluster: the credentials the 1Password Connect server itself needs to start.
Nothing in-cluster can serve that yet (ESO needs Connect running to work, and Connect needs these credentials
to run), so it's resolved from the operator's local, already-signed-in `op` CLI session at apply time via
[`op inject`](https://developer.1password.com/docs/cli/reference/commands/inject/), never stored anywhere as
a decrypted file.

[`k8s/bootstrap/kustomize/personal/external-secrets/s3cr3t.yaml`](../../k8s/bootstrap/kustomize/personal/external-secrets/s3cr3t.yaml)
contains only `op://` reference strings, not real secret material:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: onepassword-connect-credentials-secret
stringData:
  1password-credentials.json: |
    op://K8S/1password/OP_SESSION_JSON
---
apiVersion: v1
kind: Secret
metadata:
  name: onepassword-connect-vault-secret
stringData:
  OP_CONNECT_TOKEN: |-
    op://K8S/1password/OP_CONNECT_TOKEN
```

Because it *looks* like a plaintext `Secret`, the `forbid-secrets` pre-commit hook would normally reject it —
it's named `s3cr3t.yaml` (not `secret.yaml`) specifically to dodge that filename heuristic, and is the one
deliberate, explicit exception carved out in
[`.pre-commit-config.yaml`](../../.pre-commit-config.yaml):

```yaml
- id: forbid-secrets
  exclude: ^k8s/bootstrap/kustomize/personal/external-secrets/s3cr3t.yaml$  # allow committing this file, but not others
```

The `core` stage of `just bootstrap::cluster --env <env>` (see
[`k8s/bootstrap/mod.just`](../../k8s/bootstrap/mod.just)) renders this file and pipes it through `op inject`
before applying it directly with `kubectl`:

```sh
kustomize build k8s/bootstrap/kustomize/personal | just template - | kubectl --context admin@<env>-homelab apply --server-side --force-conflicts -f -
```

(`just template` is a thin wrapper around `minijinja-cli ... | op inject`.) This resolves the two `op://`
references against the real `K8S` 1Password vault and creates the two Kubernetes `Secret`s that seed the
1Password Connect server and its `ClusterSecretStore` — after which ESO can take over.

## In-cluster secrets: sealed-secrets vs. 1Password + ESO

Both controllers are installed the same two-stage way as everything else foundational in this repo: first by
the bootstrap helmfile ([`k8s/bootstrap/helmfile/apps/helmfile.yaml.gotmpl`](../../k8s/bootstrap/helmfile/apps/helmfile.yaml.gotmpl))
so they're healthy *before* Flux starts reconciling anything, then handed off to Flux's own `Kustomization`
for ongoing management — which is exactly why, per the convention in [`../../CLAUDE.md`](../../CLAUDE.md),
neither one's Flux `Kustomization` ever gets a `dependsOn` pointing at it: bootstrap ordering already
guarantees it.

```yaml
# k8s/bootstrap/helmfile/apps/helmfile.yaml.gotmpl (order, abridged)
- name: sealed-secrets
  needs: [kube-system/cilium]
- name: external-secrets
  needs: [kube-system/cilium]
- name: onepassword-connect
  needs: [external-secrets/external-secrets]
  hooks: [...]  # waits for the ClusterSecretStore CRD, then applies base/clustersecretstore.yaml
- name: cert-manager
  ...
- name: flux-operator
- name: flux-instance
```

### sealed-secrets — for secrets committed as ciphertext

[`k8s/infra/sealed-secrets/sealed-secrets/`](../../k8s/infra/sealed-secrets/sealed-secrets/) runs the
[bitnami-labs/sealed-secrets](https://github.com/bitnami-labs/sealed-secrets) controller. A `SealedSecret` is
encrypted client-side with `kubeseal` against the controller's public certificate and can then be committed
to Git — only the controller instance running in that specific cluster (holding the matching private key) can
decrypt it back into a normal `Secret`. Real examples in this repo:

- [`k8s/apps/network/unifi-controller/base/db-secret.sealed.yaml`](../../k8s/apps/network/unifi-controller/base/db-secret.sealed.yaml) — MongoDB credentials
- [`k8s/apps/dns/adguard/base/secret-users.yaml`](../../k8s/apps/dns/adguard/base/secret-users.yaml) — AdGuard Home user list
- [`k8s/infra/cert-manager/cert-manager/base/cloudflare-api-token.yaml`](../../k8s/infra/cert-manager/cert-manager/base/cloudflare-api-token.yaml) — the Cloudflare DNS-01 token

All follow the same shape (values here are real ciphertext, not secrets — only the controller in this cluster
can decrypt them):

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: db-secret-sealed
spec:
  encryptedData:
    mongo_user: AgBvOdOHA+G5nmnzmKSorKKpVYqGPEjLsrEyTamaeVWwVomTy...
    mongo_pass: AgBX7cdBJZ3IDhBa1M/vs7r2OIW0k6iikMC/gDuo40ENO33MC...
  template:
    metadata:
      name: db-secret-sealed
      namespace: unifi
```

Workflow, from [`k8s/infra/sealed-secrets/sealed-secrets/README.md`](../../k8s/infra/sealed-secrets/sealed-secrets/README.md):

```sh
echo -n bar | kubectl create secret generic mysecret --dry-run=client --from-file=foo=/dev/stdin -o yaml \
  | kubeseal --controller-namespace sealed-secrets -o yaml -n mynamespace --merge-into path/to/secret.yaml
```

**Known gap (was issue [#130](https://github.com/isejalabs/homelab/issues/130)):** there is no automated
backup of the controller's sealing key, and no bring-your-own-certificate setup — only a manual recovery
recipe using the raw controller key:

```sh
kubectl get secrets -n sealed-secrets -o yaml > sealed-secrets-key.yaml
kubeseal --controller-name=sealed-secrets --controller-namespace=sealed-secrets \
  < some-sealed-secret.yaml --recovery-unseal --recovery-private-key sealed-secrets-key.yaml \
  -o json | jq -r '.data."key" | @base64d'
```

If the cluster's sealed-secrets controller is ever lost without this key having been backed up separately,
every `SealedSecret` committed to Git becomes undecryptable and has to be re-sealed from scratch against a
new controller keypair. See bitnami-labs' own docs on
[backing up SealedSecrets](https://github.com/bitnami-labs/sealed-secrets?tab=readme-ov-file#how-can-i-do-a-backup-of-my-sealedsecrets)
and [bringing your own certificate](https://github.com/bitnami-labs/sealed-secrets/blob/main/docs/bring-your-own-certificates.md)
if this gets addressed later.

### 1Password + External Secrets Operator — for secrets sourced live from a vault

[`k8s/infra/external-secrets/`](../../k8s/infra/external-secrets/README.md) runs
[External Secrets Operator](https://external-secrets.io/) plus a
[1Password Connect](https://developer.1password.com/docs/connect/) server, so a secret's source of truth can
stay in a 1Password vault instead of being committed to Git at all — ESO polls the vault and materializes a
normal `Secret` in-cluster. The `ClusterSecretStore` wires ESO to Connect
([`k8s/infra/external-secrets/onepassword-connect/base/clustersecretstore.yaml`](../../k8s/infra/external-secrets/onepassword-connect/base/clustersecretstore.yaml)):

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: onepassword-connect
spec:
  provider:
    onepassword:
      connectHost: http://onepassword-connect.external-secrets.svc.cluster.local
      vaults:
        K8S: 1
      auth:
        secretRef:
          connectTokenSecretRef:
            name: onepassword-connect-vault-secret
            namespace: external-secrets
            key: OP_CONNECT_TOKEN
```

Today this is used to bootstrap Connect's own credentials (the `ExternalSecret`s in
[`k8s/infra/external-secrets/onepassword-connect/base/externalsecret.yaml`](../../k8s/infra/external-secrets/onepassword-connect/base/externalsecret.yaml)
pull the `1password` item out of the `K8S` vault) — there's a bit of a bootstrapping loop here too: Connect
needs a `Secret` to start, and ESO needs Connect running to produce that `Secret`, which is exactly what the
`op inject` bridge above breaks by seeding it once from outside the cluster. The first real app-level use of
this pattern is `kopiur-secret`'s `ExternalSecret`
([`k8s/components/apps/kopiur/secret/externalsecret.yaml`](../../k8s/components/apps/kopiur/secret/externalsecret.yaml)):
pulled into every namespace that uses `apps/storage/pvc`/`pvc-no-backup` (see
[`storage.md`](storage.md) and [`docs/kopiur-backup-restore.md`](../kopiur-backup-restore.md)), and rewritten
per-environment by the `kopiur-secret-env` transformer rather than hardcoded per app.

### Choosing between them

- **SOPS** — anything Terragrunt/OpenTofu needs, because no cluster exists yet to run a controller for it.
- **sealed-secrets** — an app-owned secret that should be versioned and reviewable alongside the manifests
  that use it, and where re-sealing on a cluster rebuild is an acceptable cost.
- **1Password + ESO** — a secret whose source of truth should live outside Git entirely (centrally rotated,
  shared with things outside the cluster, or just preferred over re-sealing per app).
