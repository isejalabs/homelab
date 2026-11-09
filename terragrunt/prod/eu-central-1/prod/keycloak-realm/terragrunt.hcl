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
# replace-domain/prefix-domain components (k8s/apps/identity/keycloak/envs/prod); scripts/ci/kustomize-build-all.sh fails
# when this URL differs from the rendered Keycloak and HTTPRoute hostnames, so change them together.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  keycloak_url = "https://auth.iseja.net"

  # The Checkmk site prod_k8s (Ultimate, on monitoring2) signs in humans through SAML, one client per realm because a
  # Checkmk SAML connection trusts a single realm. The Checkmk side is configured by hand, see docs/identity/checkmk-sso.md.
  # include_email stays off: notifications on prod_k8s are not enabled yet (#1901), and the e-mail attribute plus the
  # contact group "all" would make the user a mail recipient.
  saml_clients = {
    "prod_k8s-iseja" = {
      realm     = "iseja"
      client_id = "https://monitoring2.home.iseja.net/prod_k8s/check_mk/saml_metadata.py"
      acs_url   = "https://monitoring2.home.iseja.net/prod_k8s/check_mk/saml_acs.py?acs"
      name      = "Checkmk prod_k8s (iseja)"
    }
    "prod_k8s-admin" = {
      realm     = "admin"
      client_id = "https://monitoring2.home.iseja.net/prod_k8s/check_mk/saml_metadata.py"
      acs_url   = "https://monitoring2.home.iseja.net/prod_k8s/check_mk/saml_acs.py?acs"
      name      = "Checkmk prod_k8s (admin)"
    }
  }

  # The Community site prod (monitoring2) has neither SAML nor OIDC. The system Apache in front of it signs humans in with
  # mod_auth_openidc and hands the user name to Checkmk in a header, see docs/identity/checkmk-sso.md. One client per
  # realm and entry point, because Checkmk is reached under two host names: monitoring2.home.iseja.net (realm iseja) and
  # monitoring.home.iseja.net (realm admin, for the WebAuthn-protected administrators). The generated secrets land in
  # the 1Password items keycloak-oidc-checkmk-prod-<realm>#prod (vault K8S), from which Salt reads them for the Apache.
  oidc_clients = {
    "checkmk-prod-iseja" = {
      realm                     = "iseja"
      name                      = "Checkmk prod (iseja)"
      redirect_uris             = ["https://monitoring2.home.iseja.net/prod/oidc-redirect"]
      post_logout_redirect_uris = ["https://monitoring2.home.iseja.net/*"]
      secret_item_title         = "keycloak-oidc-checkmk-prod-iseja#prod"
    }
    "checkmk-prod-admin" = {
      realm                     = "admin"
      name                      = "Checkmk prod (admin)"
      redirect_uris             = ["https://monitoring.home.iseja.net/prod/oidc-redirect"]
      post_logout_redirect_uris = ["https://monitoring.home.iseja.net/*"]
      secret_item_title         = "keycloak-oidc-checkmk-prod-admin#prod"
    }
  }
}
