variable "name_prefix" {
  description = "Prefix for IP set names (e.g. <Account>-<Env>). The Web ACL name itself is FMS-controlled and ignored."
  type        = string
}

variable "web_acl_name" {
  description = "Name of the FMS-deployed CLOUDFRONT Web ACL to import and manage. Value is ignored after import (FMS controls it) via lifecycle.ignore_changes."
  type        = string
}

variable "managed_rules_enabled" {
  description = "Add AWS managed rule groups (Common, SQLi, Known Bad Inputs) and the rate-limit rule ahead of the per-domain allow rules. ~1100 WCU; the ACL ceiling is 5000."
  type        = bool
  default     = true
}

variable "rate_limit" {
  description = "Rate-based rule: max requests per 5-minute window per source IP. Only used when managed_rules_enabled."
  type        = number
  default     = 2000
}

variable "domains" {
  description = <<-EOT
    Per-domain ALLOW policy for the default-block Web ACL. default_action is block,
    so any request to a Host not matched by an allow rule generated here is BLOCKED.
    A domain MUST appear here or it is fully blocked; an unrestricted domain must
    allow ["0.0.0.0/0"] (IPv4 only — see below).

    Keyed by the public FQDN (matched case-insensitively against the request Host).
      - allowed_cidrs: base allowlist for the domain (IPv4), covering every path
        EXCEPT those carved out by path_rules. Empty list = no base allow (domain
        reachable only via its path_rules). IPv6 is not allowlisted, so all IPv6
        traffic is blocked by default_action.
      - path_rules: stricter per-path allowlists. Each path is excluded from the base
        rule and governed only by its own list. Empty allowed_cidrs = path fully
        blocked (carved out of base, no allow rule). `path` must be unique per domain.
  EOT
  type = map(object({
    allowed_cidrs = list(string)
    path_rules = optional(list(object({
      path          = string
      allowed_cidrs = list(string)
    })), [])
  }))
  default = {}
}
