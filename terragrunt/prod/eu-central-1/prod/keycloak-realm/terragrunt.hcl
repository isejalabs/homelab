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
locals {
  # The Proxmox VE cluster nodes, which each serve the web UI on their own FQDN (Let's Encrypt certificate per node).
  proxmox_nodes = ["pve1", "pve4", "pve5", "pve6"]
}

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

  # OIDC clients. The secret of each goes to the 1Password item keycloak-oidc-<key>#prod (oidc_secret_item_title_format in
  # _envcommon/keycloak-realm.hcl).
  #
  # Proxmox VE (cluster ISEJA-Lab, four nodes) signs in humans through OpenID Connect, one client per realm because a
  # Proxmox OpenID realm trusts a single issuer. Proxmox sends the address the browser used as the redirect URI, so every
  # node FQDN is listed, with and without a trailing slash. The Proxmox side (realms, groups, ACLs) is the unit
  # proxmox-access, see docs/identity/proxmox-sso.md.
  #
  # The Community site prod (monitoring2) has neither SAML nor OIDC. The system Apache in front of it signs humans in with
  # mod_auth_openidc and hands the user name to Checkmk in a header, see docs/identity/checkmk-sso.md. One client per
  # realm and entry point, because Checkmk is reached under two host names: monitoring2.home.iseja.net (realm iseja) and
  # monitoring.home.iseja.net (realm admin, for the WebAuthn-protected administrators). Salt reads the secrets from the
  # 1Password items for the Apache.
  oidc_clients = {
    "proxmox-iseja" = {
      realm     = "iseja"
      client_id = "proxmox-iseja"
      name      = "Proxmox VE (iseja)"
      redirect_uris = concat(
        [for n in local.proxmox_nodes : "https://${n}.home.iseja.net:8006"],
        [for n in local.proxmox_nodes : "https://${n}.home.iseja.net:8006/"],
      )
    }
    "proxmox-admin" = {
      realm     = "admin"
      client_id = "proxmox-admin"
      name      = "Proxmox VE (admin)"
      redirect_uris = concat(
        [for n in local.proxmox_nodes : "https://${n}.home.iseja.net:8006"],
        [for n in local.proxmox_nodes : "https://${n}.home.iseja.net:8006/"],
      )
    }
    "checkmk-prod-iseja" = {
      realm                     = "iseja"
      name                      = "Checkmk prod (iseja)"
      redirect_uris             = ["https://monitoring2.home.iseja.net/prod/oidc-redirect"]
      post_logout_redirect_uris = ["https://monitoring2.home.iseja.net/*"]
    }
    "checkmk-prod-admin" = {
      realm                     = "admin"
      name                      = "Checkmk prod (admin)"
      redirect_uris             = ["https://monitoring.home.iseja.net/prod/oidc-redirect"]
      post_logout_redirect_uris = ["https://monitoring.home.iseja.net/*"]
    }

    # The Longhorn dashboard has no login of its own: the oauth2-proxy of k8s/infra/longhorn-system/longhorn-auth logs in
    # with this client (realm admin, group sec.app.longhorn.admin), see docs/identity/longhorn-sso.md.
    "longhorn-admin" = {
      realm         = "admin"
      client_id     = "longhorn"
      redirect_uris = ["${format(include.envcommon.locals.app_url_format, "longhorn")}/oauth2/callback"]
      pkce          = true
    }

    # The OPNsense gateways gw2 and gw3 are configured by hand; the os-sso plugin on each box logs the administrators in
    # with this client (realm admin, group sec.app.opnsense.admin), see docs/identity/opnsense-auth.md and ADR 0020. Each
    # box is reached by its own name, so both callbacks are listed. The secret lands in the item
    # keycloak-oidc-opnsense-admin#prod, which is read by hand when the server entry is added on the box.
    "opnsense-admin" = {
      realm     = "admin"
      client_id = "opnsense"
      name      = "OPNsense (admin)"
      redirect_uris = [
        "https://gw2.home.iseja.net/api/sso/oidc/callback",
        "https://gw3.home.iseja.net/api/sso/oidc/callback",
      ]
      pkce = true
    }
  }
}
