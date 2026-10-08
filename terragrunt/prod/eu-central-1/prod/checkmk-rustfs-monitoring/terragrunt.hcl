# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION
# This is the configuration for Terragrunt, a thin wrapper for Terraform and OpenTofu that helps keep your code DRY and
# maintainable: https://github.com/gruntwork-io/terragrunt
# ---------------------------------------------------------------------------------------------------------------------

# Include the root `terragrunt.hcl` configuration. The root configuration contains settings that are common across all
# components and environments, such as how to configure remote state.
include "root" {
  path = find_in_parent_folders("root.hcl")
  # We want to reference the variables from the included config in this configuration, so we expose it.
  expose = true
}

# Include the envcommon configuration for the component. The envcommon configuration contains settings that are common
# for the component across all environments.
include "envcommon" {
  path = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/checkmk-rustfs-monitoring.hcl"
  # We want to reference the variables from the included config in this configuration, so we expose it.
  expose = true
}

terraform {
  source = include.envcommon.locals.base_source_url
}

# ---------------------------------------------------------------------------------------------------------------------
# Unit-specific configuration
# This component is a singleton (one Checkmk site), so the site-specific values live here and not in the envcommon.
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  # A dedicated API-only host: a special-agent rule on fiona.home.iseja.net itself (a host with the normal Checkmk agent)
  # would replace its agent connection and silence its existing checks. The folder must already exist.
  host_name = "rustfs.fiona.home.iseja.net"
  folder    = "/container/pve4"

  # Keep false until the RustFS quota special agent plugin (which defines the ruleset special_agents:rustfs_quota) is
  # installed on the Checkmk site; Checkmk rejects a rule for a ruleset it does not know.
  rules_enabled = false
}
