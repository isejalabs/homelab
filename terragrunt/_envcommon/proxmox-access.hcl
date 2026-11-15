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
    proxmox = {
      cluster_name = "ci-placeholder"
      endpoint     = "https://ci-placeholder:8006"
      insecure     = true
      username     = "ci-placeholder"
    }
    proxmox_api_token = "ci-placeholder"
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
  base_source_url = "git::https://github.com/isejalabs/terraform-modules.git//modules/proxmox-access?ref=proxmox-access-v0.1.0"

  # 1Password "K8S" vault, shared with other components -- see global.hcl.
  onepassword_vault_id = local.global_vars.locals.onepassword_vault_id
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we have to pass in to use the module. This defines the parameters that are common across all
# environments.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  onepassword          = local.secret_vars.onepassword
  onepassword_vault_id = local.onepassword_vault_id

  # The same Proxmox endpoint and API token (user terraform@pve) that the cluster units use. The token is only used to
  # call the API, never changed.
  proxmox = {
    endpoint  = local.secret_vars.proxmox.endpoint
    insecure  = local.secret_vars.proxmox.insecure
    api_token = local.secret_vars.proxmox_api_token
  }
}
