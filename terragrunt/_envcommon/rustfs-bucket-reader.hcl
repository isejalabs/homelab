# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION
# This is the common component configuration. The common variables for each environment to deploy the component
# are defined here. This configuration will be merged into the environment configuration via an include block.
# ---------------------------------------------------------------------------------------------------------------------

locals {
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

  # TEMPORARY: tracks the module's feature branch because no release tag exists yet. Switch to a tag
  # (rustfs-bucket-reader-v0.1.0, as rustfs-kopiur-backup does) before merging.
  base_source_url = "git::https://github.com/isejalabs/terraform-modules.git//modules/rustfs-bucket-reader?ref=issue/34_rustfs-bucket-reader-claude"

  # Every bucket the monitoring user may read the quota of: each environment's kopiur backup bucket, plus the
  # Longhorn backup buckets of the environments that run Longhorn's S3 backup target. Names are fixed by the
  # rustfs-kopiur-backup module ("<env>-kopiur-backup") and the longhorn-core backup-target.yaml overlays
  # ("<env>-longhorn-backup"). The module only references them by name, it doesn't manage them.
  kopiur_envs   = ["dbg", "dev", "head", "poc", "prod", "qa", "rebuild", "src"]
  longhorn_envs = ["dev", "prod", "qa", "rebuild"]
  buckets = concat(
    [for env in local.kopiur_envs : "${env}-kopiur-backup"],
    [for env in local.longhorn_envs : "${env}-longhorn-backup"],
  )

  # 1Password "K8S" vault -- not a secret, just an identifier, so it's fine to hardcode.
  onepassword_vault_id = "nem6h2jif62oiudpwmbby4yjh4"
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

  buckets              = local.buckets
  onepassword_vault_id = local.onepassword_vault_id
}
