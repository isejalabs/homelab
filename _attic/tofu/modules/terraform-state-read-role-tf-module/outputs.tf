output "assume_policy" {
  description = "The policy allowing assumption of the role that can read the Terraform state for this example."
  value       = module.example.assume_policy
}

output "policy" {
  description = "The policy that can read the Terraform state for this example."
  value       = module.example.policy
}

output "role" {
  description = "The role that can read the Terraform state for this example."
  value       = module.example.role
}
