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
# replace-domain/prefix-domain components (k8s/apps/identity/keycloak/envs/dev); scripts/ci/kustomize-build-all.sh fails
# when this URL differs from the rendered Keycloak and HTTPRoute hostnames, so change them together.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  keycloak_url = "https://dev-auth.dev.iseja.net"

  # The Checkmk site dev_k8s (Ultimate, on monitoring1) signs in humans through SAML, one client per realm because a
  # Checkmk SAML connection trusts a single realm. The Checkmk side is configured by hand, see docs/identity/checkmk-sso.md.
  # include_email is on for the iseja client: a Checkmk user without an address makes the notification fail (#2294).
  # Notifications of dev_k8s are switched off in Checkmk where they are not wanted.
  saml_clients = {
    "dev_k8s-iseja" = {
      realm         = "iseja"
      client_id     = "https://monitoring1.home.iseja.net/dev_k8s/check_mk/saml_metadata.py"
      acs_url       = "https://monitoring1.home.iseja.net/dev_k8s/check_mk/saml_acs.py?acs"
      name          = "Checkmk dev_k8s (iseja)"
      include_email = true
    }
    "dev_k8s-admin" = {
      realm     = "admin"
      client_id = "https://monitoring1.home.iseja.net/dev_k8s/check_mk/saml_metadata.py"
      acs_url   = "https://monitoring1.home.iseja.net/dev_k8s/check_mk/saml_acs.py?acs"
      name      = "Checkmk dev_k8s (admin)"
    }
  }

  # OIDC clients, one per application and realm; see docs/identity/keycloak-realms.md#oidc-clients. The Longhorn
  # dashboard has no login of its own: the oauth2-proxy of k8s/infra/longhorn-system/longhorn-auth logs in with this
  # client (realm admin, group sec.app.longhorn.admin). The generated secret lands in the 1Password item
  # keycloak-oidc-longhorn-admin#dev, which an ExternalSecret hands to the proxy.
  oidc_clients = {
    "longhorn-admin" = {
      realm         = "admin"
      client_id     = "longhorn"
      redirect_uris = ["${format(include.envcommon.locals.app_url_format, "longhorn")}/oauth2/callback"]
      pkce          = true
    }
  }
}
