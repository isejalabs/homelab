output "bucket_name" {
  value = rustfs_bucket.this.name
}

output "policy_name" {
  value = rustfs_policy.this.name
}

output "access_key" {
  value = rustfs_user.this.access_key
}

output "secret_key" {
  value     = rustfs_user.this.secret_key
  sensitive = true
}
