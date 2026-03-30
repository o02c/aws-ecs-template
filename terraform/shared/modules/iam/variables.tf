variable "users" {
  description = "Map of IAM users to create"
  type = map(object({
    path   = optional(string, "/")
    groups = optional(list(string), [])
  }))
  default = {}
}

variable "groups" {
  description = "Map of IAM groups to create"
  type = map(object({
    path        = optional(string, "/")
    policy_arns = optional(list(string), [])
  }))
  default = {}
}
