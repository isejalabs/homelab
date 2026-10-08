# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION
# This is the common component configuration. The common variables for each environment to deploy the component
# are defined here. This configuration will be merged into the environment configuration via an include block.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Automatically load global-level variables
  global_vars = read_terragrunt_config(find_in_parent_folders("global.hcl"))

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
      endpoint = "ci-placeholder.example.com:9000"
    }
    checkmk = {
      url      = "https://ci-placeholder/site"
      username = "ci-placeholder"
      secret   = "ci-placeholder"
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

  ### Common variables for the component

  # Pinned to a tagged release rather than tracking main, so this module only picks up a new version
  # deliberately (bump the ref) instead of silently on every terraform-modules main commit.
  base_source_url = "git::https://github.com/isejalabs/terraform-modules.git//modules/checkmk-rustfs-monitoring?ref=checkmk-rustfs-monitoring-v0.1.0"

  # Environments whose RustFS monitoring identity (rustfs-bucket-reader unit) and Password Store entry
  # (checkmk-password unit) are applied. Add an environment here once both are applied.
  identity_envs = ["dev", "qa", "prod"]

  # The same RustFS endpoint the other RustFS units use (a "host:port" in the secrets, https assumed). Used by the special
  # agent to query the buckets.
  rustfs_endpoint = can(regex("^https?://", local.secret_vars.rustfs.endpoint)) ? trimsuffix(local.secret_vars.rustfs.endpoint, "/") : "https://${trimsuffix(local.secret_vars.rustfs.endpoint, "/")}"

  # One identity per environment, named like the rustfs-bucket-reader unit names its user and the checkmk-password unit
  # its Password Store entry, scoped to that environment's own buckets (the Longhorn bucket only where one exists).
  identities = { for env in local.identity_envs : env => {
    access_key  = "${env}-checkmk-monitoring"
    password_id = "${env}_checkmk_monitoring"
    buckets = concat(
      ["${env}-kopiur-backup"],
      contains(local.global_vars.locals.longhorn_backup_envs, env) ? ["${env}-longhorn-backup"] : [],
    )
  } }
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we have to pass in to use the module. The host-specific values (host name, folder, whether the
# rules are enabled) are set in the unit itself, as this component is a singleton.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  # Set some secure values that are not inherited as implicit variables from the root config.
  checkmk = local.secret_vars.checkmk

  endpoint   = local.rustfs_endpoint
  identities = local.identities
}
