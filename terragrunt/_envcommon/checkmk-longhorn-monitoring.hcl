# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION
# This is the common component configuration. The common variables for each environment to deploy the component
# are defined here. This configuration will be merged into the environment configuration via an include block.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Automatically load global-level variables
  global_vars = read_terragrunt_config(find_in_parent_folders("global.hcl"))

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
    checkmk = {
      url      = "https://ci-placeholder/site"
      username = "ci-placeholder"
      secret   = "ci-placeholder"
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

  ### Common variables for the component

  # Pinned to a tagged release rather than tracking main, so this module only picks up a new version
  # deliberately (bump the ref) instead of silently on every terraform-modules main commit.
  base_source_url = "git::https://github.com/isejalabs/terraform-modules.git//modules/checkmk-longhorn-monitoring?ref=checkmk-longhorn-monitoring-v0.1.0"

  # Environments monitored so far. Staged rollout, same precedent as checkmk-rustfs-monitoring's identity_envs: the
  # always-on environments first, not the on-demand ones (dbg/head/poc/rebuild/src) whose Longhorn would otherwise be
  # polled while stopped and just report connection failures. Add an environment here once it's been verified.
  monitored_envs = ["dev", "qa", "prod"]

  # The existing Longhorn UI route of each environment (it proxies the unauthenticated /v1/* API through, exactly
  # like opening the dashboard in a browser does): prod is unprefixed (prefix-domain is not applied there), every
  # other environment gets the env- prefix on the hostname label as well as the env subdomain -- see
  # docs/architecture/network.md's domain-and-naming section for the general pattern, verified live against dev's
  # actual HTTPRoute (dev-longhorn.dev.iseja.net).
  environments = { for env in local.monitored_envs : env => {
    endpoint = env == "prod" ? "http://longhorn.prod.iseja.net" : "http://${env}-longhorn.${env}.iseja.net"
  } }
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we have to pass in to use the module. The host-specific values (host name, folder, whether
# the rules are enabled) are set in the unit itself, as this component is a singleton.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  # Set some secure values that are not inherited as implicit variables from the root config.
  checkmk = local.secret_vars.checkmk

  environments = local.environments
}
