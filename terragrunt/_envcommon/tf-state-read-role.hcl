# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION
# This is the common component configuration. The common variables for each environment to deploy the component
# are defined here. This configuration will be merged into the environment configuration via an include block.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  ### The following is duplicate code from the `root.hcl` configuration b/c TerraGrunt does not allow
  ### including `root.hcl` here again (no 2-level includes).

  # Automatically load account-, region- and environment-level variables
  account_vars     = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  # Extract some variables we need for easy access here
  account_name   = local.account_vars.locals.account_name
  aws_account_id = local.account_vars.locals.aws_account_id
  aws_region     = local.region_vars.locals.aws_region
  env            = local.environment_vars.locals.env

  ### Common variables for the component across all environments

  # Expose the base source URL so different versions of the module can be deployed in different environments.
  # base_source_url = "git::git@github.com:cisagov/terraform-state-read-role-tf-module.git"
  # Pin module version to a specific tag to ensure consistency across environments (and to ease renovate's job).
  base_source_url = "git::git@github.com:cisagov/terraform-state-read-role-tf-module.git?ref=v1.0.0"

  # Set some values common accross all environments
  role_basename = "RW-Role"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we have to pass in to use the module. This defines the parameters that are common across all
# environments.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  # `account_id` optional per module documentation, but we need to set it, otherwise the module will not work 
  # and ignore `iam_usernames`
  account_ids = [local.aws_account_id]
  
  # not possible to use relative path here with targetting the parent directory (without <component> name)
  # terraform_state_path       = "${path_relative_to_include()}/../*/tf.tfstate"
  # ... hence we compile the path manually
  terraform_state_path = "${local.account_name}/${local.aws_region}/${local.env}/*/tf.tfstate*"
  read_only            = false

  # some other common variables are set in the module due to the 1-level include limitation
}
