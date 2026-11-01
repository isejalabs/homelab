# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION
# This is the common component configuration. The common variables for each environment to deploy the component
# are defined here. This configuration will be merged into the environment configuration via an include block.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Automatically load global- and environment-level variables
  global_vars      = read_terragrunt_config(find_in_parent_folders("global.hcl"))
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  ### The following is duplicate code from the `root.hcl` configuration b/c TerraGrunt does not allow
  ### including `root.hcl` here again (no 2-level includes).

  # Automatically load global-, account-, region-, environment- and local secrets
  # The files are SOPS encrypted, and a value in a lower placed dir. is overwriting its parent
  global_secret_vars      = try(yamldecode(sops_decrypt_file(find_in_parent_folders("global-secrets.sops.yaml"))), {})
  account_secret_vars     = try(yamldecode(sops_decrypt_file(find_in_parent_folders("account-secrets.sops.yaml"))), {})
  region_secret_vars      = try(yamldecode(sops_decrypt_file(find_in_parent_folders("region-secrets.sops.yaml"))), {})
  environment_secret_vars = try(yamldecode(sops_decrypt_file(find_in_parent_folders("env-secrets.sops.yaml"))), {})
  local_secret_vars       = try(yamldecode(sops_decrypt_file("local-secrets.sops.yaml")), {})

  # Only used when decryption fails outright (e.g. CI has no SOPS AGE key) - lets `validate` still
  # type-check without real secrets, since any real value at any level overrides this (lowest priority
  # in the merge below).
  secret_defaults = {
    onepassword = {
      service_account_token = "ci-placeholder"
    }
  }

  # Merge all secret variables into a single map
  # Lower level variables will override higher level variables due to the merge function
  secret_vars = merge(
    local.secret_defaults,
    local.global_secret_vars,
    local.account_secret_vars,
    local.region_secret_vars,
    local.environment_secret_vars,
    local.local_secret_vars,
  )

  ### Common variables for the component across all environments

  # Pinned to a tagged release rather than tracking main, so this module only picks up a new version
  # deliberately (bump the ref) instead of silently on every terraform-modules main commit.
  base_source_url = "git::https://github.com/isejalabs/terraform-modules.git//modules/keycloak-realm?ref=keycloak-realm-v0.4.0"

  # Only the env differs per environment.
  env = local.environment_vars.locals.env

  # 1Password "K8S" vault, shared with other components -- see global.hcl.
  onepassword_vault_id = local.global_vars.locals.onepassword_vault_id

  # The directory is the same UCS domain for every environment, so it is stated once here. Realm names are local to
  # one Keycloak instance, hence every environment reuses `iseja` and `admin` (ADR 0016 point 4).
  ldap_base_dn = "dc=dir,dc=iseja,dc=net"

  ldap = {
    # UCS OpenLDAP listens on 7636 (LDAPS) on the domain controllers; 636 is Samba AD's own LDAP (AD schema), not used.
    # baerbel first while adelheid is unstable (#1813); Keycloak tries the URLs in this order.
    connection_urls = [
      "ldaps://baerbel.dir.iseja.net:7636",
      "ldaps://adelheid.dir.iseja.net:7636",
    ]
    bind_dn         = "uid=keycloak-ro,cn=users,${local.ldap_base_dn}"
    bind_item_title = "keycloak-ldap-bind#${local.env}"
  }

  realms = {
    iseja = {
      display_name  = "Iseja"
      users_dn      = "cn=users,${local.ldap_base_dn}"
      user_filter   = "(memberOf=cn=idm-users,cn=groups,${local.ldap_base_dn})"
      groups_dn     = "cn=groups,${local.ldap_base_dn}"
      groups_filter = "(cn=app-*)"
    }
    admin = {
      display_name  = "Admin"
      users_dn      = "cn=users,${local.ldap_base_dn}"
      user_filter   = "(memberOf=cn=idm-admins,cn=groups,${local.ldap_base_dn})"
      groups_dn     = "cn=groups,${local.ldap_base_dn}"
      groups_filter = "(cn=app-*)"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we have to pass in to use the module. This defines the parameters that are common across all
# environments.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  # Set some secure values that are not inherited as implicit variables from the root config.
  onepassword = local.secret_vars.onepassword

  # Logs in as the service-account client of the `keycloak-automation` unit, not as the break-glass administrator.
  client_item_title    = "keycloak-terragrunt#${local.env}"
  ldap                 = local.ldap
  onepassword_vault_id = local.onepassword_vault_id
  realms               = local.realms
}
