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

  # Expose the base source URL so different versions of the module can be deployed in different environments.
  base_source_url = "git::git@github.com:isejalabs/terraform-proxmox-talos.git"

  # Set some values common accross all environments
  cilium_path    = "k8s/core/network/cilium"
  cpu_type       = "custom-x86-64-v2-AES-AVX"
  ctrl_cpu       = 2
  ctrl_disk_size = 6
  ctrl_ram       = 2432
  datastore      = "local-enc"
  dns            = ["10.8.8.8", "10.9.9.9"]
  domain         = "test.iseja.net"
  vlan_id        = 108
  work_cpu       = 2
  work_disk_size = 6
  work_ram       = 2048

  gateway_api_version = "v1.4.0" # renovate: github-releases=kubernetes-sigs/gateway-api


  # volumes
  # needs to have 500M free space on-top of actual usage, cf. #241
  pv-mongodb_size = "1024M"
  pv-unifi_size   = "500M"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we have to pass in to use the module. This defines the parameters that are common across all
# environments.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  # Set some secure values that are not inherited as implicit variables from the root config.
  proxmox           = local.secret_vars.proxmox
  proxmox_api_token = local.secret_vars.proxmox_api_token
}
