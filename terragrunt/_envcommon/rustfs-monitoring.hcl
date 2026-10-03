# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION
# Singleton identity shared by RustFS bucket-capacity checks in Checkmk's prod site.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  ### Duplicate secret loading from root.hcl because Terragrunt does not permit a second-level include.
  global_secret_vars      = try(yamldecode(sops_decrypt_file(find_in_parent_folders("global-secrets.sops.yaml"))), {})
  account_secret_vars     = try(yamldecode(sops_decrypt_file(find_in_parent_folders("account-secrets.sops.yaml"))), {})
  region_secret_vars      = try(yamldecode(sops_decrypt_file(find_in_parent_folders("region-secrets.sops.yaml"))), {})
  environment_secret_vars = try(yamldecode(sops_decrypt_file(find_in_parent_folders("env-secrets.sops.yaml"))), {})
  local_secret_vars       = try(yamldecode(sops_decrypt_file("local-secrets.sops.yaml")), {})

  secret_defaults = {
    rustfs = {
      endpoint      = "https://ci-placeholder"
      access_key    = "ci-placeholder"
      access_secret = "ci-placeholder"
    }
    onepassword = {
      service_account_token = "ci-placeholder"
    }
  }

  secret_vars = merge(
    local.secret_defaults,
    local.global_secret_vars,
    local.account_secret_vars,
    local.region_secret_vars,
    local.environment_secret_vars,
    local.local_secret_vars,
  )

  # Temporary branch pin while the reusable module PR is reviewed; replace with its release tag before applying.
  base_source_url = "git::https://github.com/isejalabs/terraform-modules.git//modules/rustfs-bucket-reader?ref=issue/34_rustfs-monitoring-identity"

  bucket_names = [
    "dbg-kopiur-backup",
    "dev-kopiur-backup",
    "head-kopiur-backup",
    "poc-kopiur-backup",
    "prod-kopiur-backup",
    "qa-kopiur-backup",
    "rebuild-kopiur-backup",
    "src-kopiur-backup",
    "dev-longhorn-backup",
    "prod-longhorn-backup",
    "qa-longhorn-backup",
    "rebuild-longhorn-backup",
  ]

  onepassword_vault_id = "nem6h2jif62oiudpwmbby4yjh4"
}

inputs = {
  name                 = "checkmk-monitoring"
  bucket_names         = local.bucket_names
  rustfs               = local.secret_vars.rustfs
  onepassword          = local.secret_vars.onepassword
  onepassword_vault_id = local.onepassword_vault_id
}
