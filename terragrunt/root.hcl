# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION
# Terragrunt is a thin wrapper for Terraform/OpenTofu that provides extra tools for working with multiple modules,
# remote state, and locking: https://github.com/gruntwork-io/terragrunt
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Automatically load account-, region- and environment-level variables
  account_vars     = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  # Automatically load global-, account-, region-, environment- and local secrets
  # The files are SOPS encrypted, and a value in a lower placed dir. is ovewriting its parent
  # The files are optional and need to be placed in
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

  # Extract some variables we need for easy access here
  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.aws_account_id
  aws_region   = local.region_vars.locals.aws_region
}

remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    path = "${path_relative_to_include()}/terraform.tfstate"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# GLOBAL PARAMETERS
# These variables apply to all configurations in this subfolder. These are automatically merged into the child
# `terragrunt.hcl` config via the include block.
# ---------------------------------------------------------------------------------------------------------------------

# Configure root level variables that all resources can inherit. This is especially helpful with multi-account configs
# where terraform_remote_state data sources are placed directly into the modules.
#
# A variable defined in a lower level will override a value defined in a higher level due to the merge function
# (e.g. env-level variables will override region-level variables, which will override account-level variables).
# 
# You can reference these variables in child modules using:
#   include.root.inputs.<variable_name>
inputs = merge(
  local.account_vars.locals,
  local.region_vars.locals,
  local.environment_vars.locals,
  local.global_secret_vars,
  local.account_secret_vars,
  local.region_secret_vars,
  local.environment_secret_vars,
  local.local_secret_vars,
)