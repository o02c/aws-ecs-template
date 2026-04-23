variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "users" {
  description = <<-EOT
    Map of IAM users to create. Each user is auto-enrolled in the mfa-enforced
    group. `groups` can list additional permission groups; those names must
    match aws_iam_group resources defined in iam_group_<name>.tf files.
  EOT
  type = map(object({
    path   = optional(string, "/")
    groups = optional(list(string), [])
  }))
  default = {}
}
