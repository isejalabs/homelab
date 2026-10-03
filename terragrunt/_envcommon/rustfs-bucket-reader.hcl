# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION
# This is the common component configuration. The common variables for each environment to deploy the component
# are defined here. This configuration will be merged into the environment configuration via an include block.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Automatically load global- and environment-level variables
  global_vars      = read_terragrunt_config(find_in_parent_folders("global.hcl"))
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  ### The following is duplicate code from the `root.hcl` configuration b/c TerraGrunt does not allow
  ### including `root.hcl` here again (no 2-level includes).

  # Automatically load global-, account-, region-, environment- and local secrets
  # The files are SOPS encrypted, and a value in a lower placed dir. is overwriting its parent
  global_secret_vars      = try(yamldecode(sops_decrypt_file(find_in_parent_folders("global-secrets.sops.yaml"))), {})
  account_secret_vars     = try(yamldecode(sops_decrypt_file(find_in_parent_folders("account-secrets.sops.yaml"))), {})
  region_secret_vars      = try(yamldecode(sops_decrypt_file(find_in_parent_folders("region-secrets.sops.yaml"))), {})
  environment_secret_vars = try(yamldecode(sops_decrypt_file(find_in_parent_folders("env-secrets.sops.yaml"))), {})
  local_secret_vars       = try(yamldecode(sops_decrypt_file("local-secrets.sops.yaml")), {})

  # Only used when decryption fails outright (e.g. CI has no SOPS AGE key) - lets `validate` still
  # type-check without real secrets, since any real value at any level overrides this (lowest priority
  # in the merge below).
  secret_defaults = {
    rustfs = {
      endpoint      = "https://ci-placeholder"
      access_key    = "ci-placeholder"
      access_secret = "ci-placeholder"
    }
    onepassword = {
      service_account_token = "ci-placeholder"
    }
  }

  # Merge all secret variables into a single map
  # Lower level variables will override higher level variables due to the merge function
  secret_vars = merge(
    local.secret_defaults,
    local.global_secret_vars,
    local.account_secret_vars,
    local.region_secret_vars,
    local.environment_secret_vars,
    local.local_secret_vars,
  )

  ### Common variables for the component across all environments

  # Pinned to a tagged release rather than tracking main, so this module only picks up a new version
  # deliberately (bump the ref) instead of silently on every terraform-modules main commit.
  base_source_url = "git::https://github.com/isejalabs/terraform-modules.git//modules/rustfs-bucket-reader?ref=rustfs-bucket-reader-v0.1.0"

  # Only the env differs per environment. Each environment gets its own monitoring identity (all of them used by the
  # one Checkmk site), scoped to that environment's own buckets only.
  env = local.environment_vars.locals.env

  # Environments with a Longhorn S3 backup target, i.e. a "<env>-longhorn-backup" bucket besides the kopiur one (see
  # the longhorn-core backup-target.yaml overlays). The module only references buckets by name, it doesn't manage them.
  longhorn_envs = ["dev", "prod", "qa", "rebuild"]
  bucket_names = concat(
    ["${local.env}-kopiur-backup"],
    contains(local.longhorn_envs, local.env) ? ["${local.env}-longhorn-backup"] : [],
  )

  # Named after consumer and environment; the module uses it verbatim as user, policy base and 1Password item title.
  name = "${local.env}-checkmk-monitoring"

  # 1Password "K8S" vault, shared with other components -- see global.hcl.
  onepassword_vault_id = local.global_vars.locals.onepassword_vault_id
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we have to pass in to use the module. This defines the parameters that are common across all
# environments.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  # Set some secure values that are not inherited as implicit variables from the root config.
  rustfs      = local.secret_vars.rustfs
  onepassword = local.secret_vars.onepassword

  name                 = local.name
  bucket_names         = local.bucket_names
  onepassword_vault_id = local.onepassword_vault_id
}
