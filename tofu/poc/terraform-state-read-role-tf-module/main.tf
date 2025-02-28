# Our primary provider is in the Terraform account
provider "aws" {
  default_tags {
    tags = {
      Testing = true
    }
  }
  # profile = "cool-terraform-provisionaccount"
  region = "eu-central-1"
}

# Provider for the Users account
provider "aws" {
  alias = "users"
  default_tags {
    tags = {
      Testing = true
    }
  }
  # profile = "cool-users-provisionaccount"
  region = "eu-central-1"
}

locals {
  env = "test3-poc"
}

#-------------------------------------------------------------------------------
# Configure the example module.
#-------------------------------------------------------------------------------
module "example" {
  # source = "git::git@github.com:cisagov/terraform-state-read-role-tf-module?ref=HEAD"
  source = "../../../../terraform-state-read-role-tf-module"
  providers = {
    aws       = aws
    aws.users = aws.users
  }

  account_ids                 = ["443370678269"]
  iam_usernames               = ["poc-terraform-state"]
  role_name                   = "${local.env}-ReadTerraformStateReadRoleTFModuleTerraformState"
  terraform_state_bucket_name = "${local.env}-tf-state-tg"
  terraform_state_path        = "*"
  # terraform_workspace         = local.env
  read_only                   = false
  lock_db_table_arn           = "arn:aws:dynamodb:eu-central-1:443370678269:table/${local.env}-tf-state-lock-tg"
}
