variable "rustfs" {
  description = "RustFS admin endpoint and credentials used to provision the bucket/policy/user."
  type = object({
    endpoint      = string
    access_key    = string
    access_secret = string
  })
  sensitive = true
}

variable "bucket_name" {
  description = "Name of the RustFS bucket to create. Also used as the dedicated bucket user's access key and as the base name for its policy."
  type        = string
}

variable "policy_actions" {
  description = "S3 actions the dedicated bucket user is allowed to perform, scoped to its own bucket only."
  type        = list(string)
  default = [
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject",
    "s3:ListBucket",
  ]
}
