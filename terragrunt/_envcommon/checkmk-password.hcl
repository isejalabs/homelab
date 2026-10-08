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
    onepassword = {
      service_account_token = "ci-placeholder"
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

  ### Common variables for the component across all environments

  # TEMPORARY: tracks the module's feature branch because no release tag exists yet. Switch to a tag
  # (checkmk-password-v0.1.0, as rustfs-kopiur-backup does) before merging.
  base_source_url = "git::https://github.com/isejalabs/terraform-modules.git//modules/checkmk-password?ref=issue/44_checkmk-password"

  # Only the env differs per environment.
  env = local.environment_vars.locals.env

  # The 1Password item written by the environment's rustfs-bucket-reader unit (see rustfs-bucket-reader.hcl: the
  # vault's "<thing>#<env>" item naming). The module reads its rustfs/SECRET_KEY field by default.
  item_title = "checkmk-monitoring#${local.env}"

  # Checkmk Password Store identifier, referenced by rules. Underscores, like the spike that verified the whole chain
  # (rule reference + agent lookup); Checkmk rejects identifiers with "." or "#" or a leading digit.
  password_id = "${local.env}_checkmk_monitoring"

  # Human-readable title, same as the RustFS user and policy base name of the environment's identity.
  title = "${local.env}-checkmk-monitoring"

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
  checkmk     = local.secret_vars.checkmk
  onepassword = local.secret_vars.onepassword

  item_title           = local.item_title
  password_id          = local.password_id
  title                = local.title
  onepassword_vault_id = local.onepassword_vault_id
}
