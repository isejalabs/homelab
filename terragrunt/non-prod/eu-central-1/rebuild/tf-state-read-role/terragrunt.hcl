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
  path = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/tf-state-read-role.hcl"
  # We want to reference the variables from the included config in this configuration, so we expose it.
  expose = true
}

# Configure the version of the module to use in this environment. This allows you to promote new versions one
# environment at a time (e.g., qa -> stage -> prod).
terraform {
  source = include.envcommon.locals.base_source_url
}

# ---------------------------------------------------------------------------------------------------------------------
# Unit-specific configuration
# This is the configuration for the specific environment. It contains settings that are specific to this environment
# ---------------------------------------------------------------------------------------------------------------------

locals {
  env            = include.root.inputs.env
  bucket_name    = include.root.locals.remote_state_bucket
  aws_account_id = include.root.locals.aws_account_id
  aws_region     = include.root.locals.aws_region
  dynamodb_table = include.root.locals.remote_state_dynamodb_table
  role_basename  = include.envcommon.locals.role_basename
  iam_usernames  = include.root.locals.secret_vars.remote_state_iam_usernames
}

inputs = {
  # array of allowed AWS userids that can assume the role
  # iam_usernames = ["foo", "bar"]
  iam_usernames = local.iam_usernames

  role_name = "${local.env}-${local.bucket_name}-${local.role_basename}"

  # get the same bucket name as used in the root remote state setup
  # placed here and not in the envcommon, due to 1-level include limitation
  terraform_state_bucket_name = local.bucket_name

  # DynamoDB table for locking actually not used (rather S3 native locking)
  # however, the module requires it for equipping the role with S3:Put write access
  lock_db_table_arn = "arn:aws:dynamodb:${local.aws_region}:${local.aws_account_id}:table/${local.dynamodb_table}"
}
