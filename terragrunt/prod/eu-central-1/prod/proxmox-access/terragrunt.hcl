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
  path = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/proxmox-access.hcl"
  # We want to reference the variables from the included config in this configuration, so we expose it.
  expose = true
}

terraform {
  source = include.envcommon.locals.base_source_url
}

# ---------------------------------------------------------------------------------------------------------------------
# Human login to the Proxmox VE cluster ISEJA-Lab (four nodes, one access configuration in /etc/pve) through the `prod`
# Keycloak: docs/identity/proxmox-sso.md. The clients are the `oidc_clients` of the unit keycloak-realm; their secrets are
# read from the 1Password items keycloak-oidc-<client>#prod. The AD realm DIR.ISEJA.NET (still the login default), `pam`,
# `root@pam` and the API tokens are not managed here.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  realms = {
    kc-admin = {
      issuer_url               = "https://auth.iseja.net/realms/admin"
      client_id                = "proxmox-admin"
      client_secret_item_title = "keycloak-oidc-proxmox-admin#prod"
      comment                  = "Keycloak realm admin (administrator accounts)"
    }
    kc-iseja = {
      issuer_url               = "https://auth.iseja.net/realms/iseja"
      client_id                = "proxmox-iseja"
      client_secret_item_title = "keycloak-oidc-proxmox-iseja#prod"
      comment                  = "Keycloak realm iseja (everyday accounts)"
    }
  }

  # The names are the UCS group (docs/identity/ucs-groups.md) with the realm ID appended by Proxmox.
  groups = {
    "sec.app.proxmox.admin-kc-admin"    = { comment = "Administrators (UCS sec.app.proxmox.admin)" }
    "sec.app.proxmox.operator-kc-iseja" = { comment = "Operators (UCS sec.app.proxmox.operator)" }
    "sec.app.proxmox.readonly-kc-iseja" = { comment = "Read-only (UCS sec.app.proxmox.readonly)" }
  }

  # PVEAuditor plus console, power and snapshot of guests; no rollback, no guest configuration, no node shell, no user or
  # realm management (docs/identity/proxmox-sso.md#roles).
  roles = {
    Operator = [
      "Datastore.Audit",
      "Mapping.Audit",
      "Pool.Audit",
      "SDN.Audit",
      "Sys.Audit",
      "VM.Audit",
      "VM.Console",
      "VM.GuestAgent.Audit",
      "VM.PowerMgmt",
      "VM.Snapshot",
    ]
  }

  acls = {
    admin    = { path = "/", role_id = "Administrator", group_id = "sec.app.proxmox.admin-kc-admin" }
    operator = { path = "/", role_id = "Operator", group_id = "sec.app.proxmox.operator-kc-iseja" }
    readonly = { path = "/", role_id = "PVEAuditor", group_id = "sec.app.proxmox.readonly-kc-iseja" }
  }
}
