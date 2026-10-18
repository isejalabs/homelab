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
  path = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/checkmk-longhorn-monitoring.hcl"
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
  # One dedicated API-only host per environment, with its real Longhorn hostname (module v0.2.0+ derives it from
  # each environment's endpoint). The folder must already exist; reusing the same /misc folder
  # checkmk-rustfs-monitoring's API-only hosts live in.
  folder = "/misc"

  # Longhorn disk polling, per the monitoring plan: start at five minutes, matching the standard service interval
  # (15 minutes is also acceptable where sufficient, but five is where this starts).
  check_interval_minutes = 5

  # The special-agent rules need the longhorn_capacity plugin package (isejalabs/checkmk-modules#8, released and
  # installed on the Checkmk site through Salt on monitoring2, confirmed via `mkp list`): Checkmk rejects a rule
  # for a ruleset it does not know. Set back to false and apply BEFORE removing the plugin, same as
  # checkmk-rustfs-monitoring.
  rules_enabled = true
}
