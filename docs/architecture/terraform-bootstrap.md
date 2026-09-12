# AWS/Terraform bootstrapping

Terragrunt's remote-state backend is S3, and the IAM role each environment assumes to reach it is itself
provisioned *by* Terragrunt. That's a chicken-and-egg problem: something has to create the S3 bucket and the
first IAM identity before any `terragrunt` command in this repo can run at all. This doc explains what's
actually automated (in code, in this repo) versus what has to happen manually, once, outside of it.

Everything described as "manual" below is a one-time setup step already performed for this homelab's AWS
account — it isn't part of `just bootstrap::cluster` or any script in `scripts/`, and there's no code in this
repo (nor in the retired `_attic/`) that creates it. If you're ever re-bootstrapping the AWS side from zero,
treat this section as the missing runbook.

## The S3 remote-state backend

[`terragrunt/root.hcl`](../../terragrunt/root.hcl) is included by every module and wires the backend:

```hcl
locals {
  project_name                 = "homelab"
  resource_basename            = "${get_env("TG_BUCKET_PREFIX", "")}${local.account_name}-${local.project_name}-${local.aws_region}"
  remote_state_bucket_basename = "${local.resource_basename}-tf-state"
  remote_state_bucket          = "${local.remote_state_bucket_basename}-${local.aws_account_id}"
  remote_state_dynamodb_table  = "${local.resource_basename}-tf-state-lock"
}

remote_state {
  backend = "s3"
  config = {
    key     = "${path_relative_to_include()}/tf.tfstate"
    bucket  = local.remote_state_bucket
    region  = local.aws_region
    encrypt = true
    # The DynamoDB table could be used for state locking, but we use S3 native locking instead
    # dynamodb_table = local.remote_state_dynamodb_table
    use_lockfile = true
  }
  encryption = {
    key_provider = "pbkdf2"
    passphrase   = local.secret_vars.state_encryption_passphrase
  }
}
```

- Bucket name: `<account_name>-homelab-<aws_region>-tf-state-<aws_account_id>`, one bucket per AWS account
  (see below), one `key` per module (`<path_relative_to_include()>/tf.tfstate`).
- Locking is S3-native (`use_lockfile = true`), not DynamoDB — `remote_state_dynamodb_table` is computed and
  its ARN is still handed to the IAM role module below (which needs it to grant `dynamodb:*` permissions even
  though nothing currently writes lock rows there), but no DynamoDB table is actually provisioned by any code
  in this repo.
- On top of S3's own `encrypt = true` (SSE), Terragrunt additionally encrypts state client-side with `pbkdf2`
  using `state_encryption_passphrase` — a SOPS secret (see [`secrets.md`](secrets.md)). This is the detail
  that makes the bootstrap order matter: decrypting that passphrase is a prerequisite for touching state at
  all, so the age key used for SOPS has to exist before the very first `terragrunt init`.

**Nothing in this repo creates the S3 bucket itself.** There is no `aws_s3_bucket` resource anywhere under
`terragrunt/` (or in the retired `_attic/`) — `root.hcl` only ever *references*
`local.remote_state_bucket` as a backend target. The bucket has to already exist by the time the very first
`terragrunt` command in a fresh AWS account runs.

## The state-read/write IAM role

[`terragrunt/_envcommon/tf-state-read-role.hcl`](../../terragrunt/_envcommon/tf-state-read-role.hcl) wraps an
external community module,
[`cisagov/terraform-state-read-role-tf-module`](https://github.com/cisagov/terraform-state-read-role-tf-module)
(pinned to `v1.0.0`), and every environment has its own instance of it under
`terragrunt/<non-prod|prod>/eu-central-1/<env>/tf-state-read-role/terragrunt.hcl`, e.g.
[`terragrunt/non-prod/eu-central-1/dev/tf-state-read-role/terragrunt.hcl`](../../terragrunt/non-prod/eu-central-1/dev/tf-state-read-role/terragrunt.hcl):

```hcl
locals {
  iam_usernames = include.root.locals.secret_vars.remote_state_iam_usernames
}

inputs = {
  iam_usernames                = local.iam_usernames
  role_name                    = "${local.env}-${local.bucket_name}-${local.role_basename}"
  terraform_state_bucket_name  = local.bucket_name
  lock_db_table_arn            = "arn:aws:dynamodb:${local.aws_region}:${local.aws_account_id}:table/${local.dynamodb_table}"
}
```

This module **creates an IAM role** per environment (an "`RW-Role`") scoped to that environment's slice of
the shared state bucket (`terraform_state_path = "<account>/<region>/<env>/*/tf.tfstate*"` from
`_envcommon/tf-state-read-role.hcl`), and grants a set of **already-existing** IAM users
(`remote_state_iam_usernames`, a SOPS secret at the account level — see
[`secrets.md`](secrets.md#sops-provisioning-secrets)) permission to assume it. **It does not create those IAM
users** — they're passed in by name as pre-existing principals.

Every non-prod environment's `.envrc` exports the resulting role ARN as `TG_IAM_ASSUME_ROLE`, e.g.
[`terragrunt/non-prod/eu-central-1/dev/.envrc`](../../terragrunt/non-prod/eu-central-1/dev/.envrc):

```sh
export TG_IAM_ASSUME_ROLE="arn:aws:iam::443370678269:role/dev-non-prod-homelab-eu-central-1-tf-state-443370678269-RW-Role"
```

`TG_IAM_ASSUME_ROLE` is a built-in Terragrunt variable, consumed natively by the `terragrunt` binary itself
(not custom logic in this repo) — it makes Terragrunt assume that role for both backend S3 access and the AWS
provider. This is also the source of the gotcha already called out in [`../../CLAUDE.md`](../../CLAUDE.md):
`direnv` sources `.envrc` automatically in an interactive shell, but a non-interactive agent shell has to
`source` it explicitly before running `terragrunt plan`/`apply`, or every command fails with a generic S3
`HeadObject`/`403 Forbidden` that looks like an unrelated credentials problem.

One naming quirk worth knowing: the generated role name can exceed AWS's 64-character IAM role-name limit and
gets silently truncated, e.g.
[`terragrunt/non-prod/eu-central-1/rebuild/.envrc`](../../terragrunt/non-prod/eu-central-1/rebuild/.envrc)
references `...tf-state-443370678269-RW-R` (not `...RW-Role`) — if a new environment's role ARN doesn't match
what you'd naively construct from the naming pattern, check the actual role name in IAM rather than assuming
a typo.

## `account.hcl` / `region.hcl` / `env.hcl`

`root.hcl` merges these the same way it merges SOPS secrets — locals only, no secret material:

```hcl
account_vars     = read_terragrunt_config(find_in_parent_folders("account.hcl"))
region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))
environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

plain_vars = merge(local.account_vars.locals, local.region_vars.locals, local.environment_vars.locals)
```

directory layout `terragrunt/<non-prod|prod>/account.hcl` → `.../eu-central-1/region.hcl` →
`.../eu-central-1/<env>/env.hcl`.

**`non-prod` and `prod` are not separate AWS accounts** — despite the directory split implying account-level
isolation, both [`terragrunt/non-prod/account.hcl`](../../terragrunt/non-prod/account.hcl) and
[`terragrunt/prod/account.hcl`](../../terragrunt/prod/account.hcl) set the identical
`aws_account_id = "443370678269"`:

```hcl
# terragrunt/non-prod/account.hcl
locals {
  account_name   = "non-prod"
  aws_account_id = "443370678269"
}
```

`account_name` is a purely logical/naming prefix used to build distinct bucket keys and IAM role names —
isolation between `non-prod` and `prod` state comes from separate S3 key prefixes and separate IAM roles
*within the same AWS account*, not from an AWS account boundary. Worth keeping in mind before assuming "prod"
implies the usual blast-radius isolation a separate AWS account would give you.

## The actual bootstrap sequence

What's confirmed, in code:

1. Every environment's `tf-state-read-role` module creates that environment's `RW-Role`, scoped to its own
   slice of the (already-existing) state bucket, assumable only by the IAM users listed in
   `remote_state_iam_usernames`.
2. Every other module (`vehagn-k8s`, `vms`, `talos-proxmox`) includes `root.hcl`, targets the same S3 backend,
   and relies on its environment's `.envrc` to set `TG_IAM_ASSUME_ROLE` so Terragrunt assumes the right role
   automatically.

What is genuinely **not** in this repo — one-time manual setup, done once outside IaC, with no corresponding
script or module:

- **The AWS account itself** (`443370678269`, shared by both `non-prod` and `prod`).
- **The S3 state bucket** (`<account>-homelab-eu-central-1-tf-state-443370678269`) and its bucket
  policy/versioning/encryption settings — created by hand (console or CLI) before the very first
  `tf-state-read-role` apply could store its own state anywhere.
- **The initial IAM user(s)** referenced by `remote_state_iam_usernames` — no `aws_iam_user` resource exists
  anywhere in the repo; these are pre-existing principals the `tf-state-read-role` module only grants
  `sts:AssumeRole` permission to, never manages. (The retired `_attic/tofu/modules/terraform-state-read-role-tf-module/main.tf`
  test harness uses a plain string like `iam_usernames = ["poc-terraform-state"]` as example input — useful
  to see the *shape* expected, but it's local test data, not evidence of what the real account's users are
  named.)
- **How the very first `tf-state-read-role` apply's own state was stored** before the S3 backend existed for
  it to target — whether it briefly ran with local state and was migrated in afterward, or the bucket already
  existed by the time this repo's first commit touching `root.hcl` landed. There's no trace of this either
  way (no local `.tfstate` file, no migration script, no comment), and this repo's git history doesn't reach
  back far enough to settle it. Treat it as presumed, not evidenced.
- **The DynamoDB lock table** — referenced by ARN (the IAM role needs `dynamodb:*` permissions on it to
  satisfy the module's requirements) but never actually used for locking and never provisioned by any code
  here.

If you're redoing this from scratch for a new AWS account, the missing steps are, in order: create the
account, create an IAM user (or SSO identity) with enough privilege to create S3 buckets and IAM roles,
create the state bucket by hand with versioning + encryption enabled, populate
`account-secrets.sops.yaml`/`global-secrets.sops.yaml` with `state_encryption_passphrase` and
`remote_state_iam_usernames` for that user, then run `terragrunt apply` inside each environment's
`tf-state-read-role` directory to create the roles — after that, `.envrc`'s `TG_IAM_ASSUME_ROLE` takes over
and every other module works normally.
