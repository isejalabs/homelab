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
  path = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/keycloak-realm.hcl"
  # We want to reference the variables from the included config in this configuration, so we expose it.
  expose = true
}

terraform {
  source = include.envcommon.locals.base_source_url
}

# ---------------------------------------------------------------------------------------------------------------------
# Only the Keycloak URL is specific to this environment. The hostname is derived per environment by the
# replace-domain/prefix-domain components (k8s/apps/identity/keycloak/envs/qa); scripts/kustomize-build-all.sh fails
# when this URL differs from the rendered Keycloak and HTTPRoute hostnames, so change them together.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  keycloak_url = "https://qa-auth.qa.iseja.net"

  # The Checkmk site qa_k8s (Ultimate, on monitoring1) signs in humans through SAML, one client per realm because a
  # Checkmk SAML connection trusts a single realm. The Checkmk side is configured by hand, see docs/identity/checkmk-sso.md.
  saml_clients = {
    "qa_k8s-iseja" = {
      realm         = "iseja"
      client_id     = "https://monitoring1.home.iseja.net/qa_k8s/check_mk/saml_metadata.py"
      acs_url       = "https://monitoring1.home.iseja.net/qa_k8s/check_mk/saml_acs.py?acs"
      name          = "Checkmk qa_k8s (iseja)"
      include_email = true
    }
    "qa_k8s-admin" = {
      realm     = "admin"
      client_id = "https://monitoring1.home.iseja.net/qa_k8s/check_mk/saml_metadata.py"
      acs_url   = "https://monitoring1.home.iseja.net/qa_k8s/check_mk/saml_acs.py?acs"
      name      = "Checkmk qa_k8s (admin)"
    }
  }
}
