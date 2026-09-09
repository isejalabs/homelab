provider "rustfs" {
  endpoint      = var.rustfs.endpoint
  access_key    = var.rustfs.access_key
  access_secret = var.rustfs.access_secret
}

resource "rustfs_bucket" "this" {
  name = var.name
}

# Scopes the dedicated user down to only this bucket, rather than reusing the admin credentials.
resource "rustfs_policy" "this" {
  name    = "${var.name}-rw"
  version = "2012-10-17"

  statement {
    effect = "Allow"
    action = var.policy_actions
    ressource = [
      "arn:aws:s3:::${rustfs_bucket.this.name}",
      "arn:aws:s3:::${rustfs_bucket.this.name}/*",
    ]
  }
}

resource "random_password" "user_secret" {
  length  = 40
  special = false
}

resource "rustfs_user" "this" {
  access_key = var.name
  secret_key = random_password.user_secret.result
  status     = "enabled"
  policy     = rustfs_policy.this.name
}
