# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION
# This is the common component configuration. The common variables for each environment to deploy the component
# are defined here. This configuration will be merged into the environment configuration via an include block.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Expose the base source URL so different versions of the module can be deployed in different environments.
  base_source_url = "git::git@github.com:isejalabs/terraform-proxmox-talos.git"

  # Set some values common accross all environments
  cpu_type     = "x86-64-v2-AES"
  datastore_id = "local-enc"
  cilium_path  = "k8s/core/network/cilium"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we have to pass in to use the module. This defines the parameters that are common across all
# environments.
# ---------------------------------------------------------------------------------------------------------------------
# inputs = {
# }
