# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION
# This is the singleton RustFS monitoring identity used by Checkmk's prod site.
# ---------------------------------------------------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/rustfs-monitoring.hcl"
  expose = true
}

terraform {
  source = include.envcommon.locals.base_source_url
}
