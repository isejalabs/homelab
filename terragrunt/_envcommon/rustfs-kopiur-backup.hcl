# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION
# This is the common component configuration. The common variables for each environment to deploy the component
# are defined here. This configuration will be merged into the environment configuration via an include block.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  ### The following is duplicate code from the `root.hcl` configuration b/c TerraGrunt does not allow
  ### including `root.hcl` here again (no 2-level includes).

  # Automatically load account-, region- and environment-level variables
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  # Automatically load global-, account-, region-, environment- and local secrets
  # The files are SOPS encrypted, and a value in a lower placed dir. is overwriting its parent
  global_secret_vars      = try(yamldecode(sops_decrypt_file(find_in_parent_folders("global-secrets.sops.yaml"))), {})
  account_secret_vars     = try(yamldecode(sops_decrypt_file(find_in_parent_folders("account-secrets.sops.yaml"))), {})
  region_secret_vars      = try(yamldecode(sops_decrypt_file(find_in_parent_folders("region-secrets.sops.yaml"))), {})
  environment_secret_vars = try(yamldecode(sops_decrypt_file(find_in_parent_folders("env-secrets.sops.yaml"))), {})
  local_secret_vars       = try(yamldecode(sops_decrypt_file("local-secrets.sops.yaml")), {})

  # Merge all secret variables into a single map
  # Lower level variables will override higher level variables due to the merge function
  secret_vars = merge(
    local.global_secret_vars,
    local.account_secret_vars,
    local.region_secret_vars,
    local.environment_secret_vars,
    local.local_secret_vars,
  )

  ### Common variables for the component across all environments

  base_source_url = "git::https://github.com/isejalabs/terraform-modules.git//modules/rustfs-kopiur-backup"

  # Only the env differs per environment -- computed here so per-env units don't repeat it. The module
  # derives both the bucket/user/policy name and the 1Password item title from this plus its own
  # `name` default ("kopiur-backup"), so that string isn't repeated here.
  env = local.environment_vars.locals.env

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
  env         = local.env

  onepassword_vault_id = local.onepassword_vault_id
}
