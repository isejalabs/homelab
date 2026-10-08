# ---------------------------------------------------------------------------------------------------------------------
# GLOBAL (NON-SECRET) VARIABLES
# Values shared by every environment and component that aren't secret, so they're stated once here instead of in each
# _envcommon file. Read from there via `read_terragrunt_config(find_in_parent_folders("global.hcl"))`.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # 1Password "K8S" vault -- not a secret, just an identifier, so it's fine to hardcode.
  onepassword_vault_id = "nem6h2jif62oiudpwmbby4yjh4"

  # Environments with a Longhorn S3 backup target, i.e. a "<env>-longhorn-backup" RustFS bucket besides the
  # "<env>-kopiur-backup" one (see the longhorn-core backup-target.yaml overlays). Used by the RustFS monitoring
  # identities and their Checkmk rules; scripts/rustfs-verify-monitoring.sh mirrors it in shell.
  longhorn_backup_envs = ["dev", "prod", "qa", "rebuild"]
}
