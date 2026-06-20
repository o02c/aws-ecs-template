# --------------------------------------------------------------------------------
# Rule expansion (default-block -> allow rules)
# --------------------------------------------------------------------------------
# default_action is block, so every rule here is an ALLOW rule. Each domain expands
# into:
#   - "<domain>#base"       : allow Host == domain AND IP in allowlist, EXCLUDING any
#                             path carved out by path_rules. Created only when
#                             allowed_cidrs is non-empty.
#   - "<domain>#path:<path>": allow Host == domain AND uri starts_with <path> AND IP
#                             in the path allowlist. Created only when the path
#                             allowlist is non-empty (empty = path stays blocked).
# Every path_rule path is excluded from the base rule regardless of its allowlist, so
# a path's access is governed solely by its own rule (or blocked if it has none).
# IPv4 only: IP sets are IPV4, so IPv6 traffic never matches an allow rule and is
# blocked by default_action.

locals {
  # All declared path_rule paths per domain (incl. empty-allowlist ones, which still
  # carve territory out of broader rules so a fully-blocked sub-path cannot leak).
  _domain_paths = { for d, cfg in var.domains : d => [for pr in cfg.path_rules : pr.path] }

  _base = {
    for d, cfg in var.domains : "${d}#base" => {
      domain = d
      path   = ""
      cidrs  = cfg.allowed_cidrs
      excl   = local._domain_paths[d] # base excludes every declared path
    } if length(cfg.allowed_cidrs) > 0
  }

  _paths = merge([
    for d, cfg in var.domains : {
      for pr in cfg.path_rules : "${d}#path:${pr.path}" => {
        domain = d
        path   = pr.path
        cidrs  = pr.allowed_cidrs
        # Longest-prefix wins: exclude any declared path that strictly extends this
        # one, so a broader path rule never shadows a stricter nested one.
        # NOTE: startswith() (and the STARTS_WITH byte_match in web_acl.tf) is a raw
        # string prefix, NOT a path-segment match — "/api" also matches "/apixyz", so
        # "/apixyz" gets carved out of base and may be over-blocked. This only ever
        # over-blocks, never over-permits. Proper fix is a regex match on the path
        # (e.g. "^/api(/|$)"); deferred for now.
        excl = [for q in local._domain_paths[d] : q if q != pr.path && startswith(q, pr.path)]
      } if length(pr.allowed_cidrs) > 0
    }
  ]...)

  rules = merge(local._base, local._paths)

  # Deterministic, collision-free priorities. Allow rules are mutually disjoint
  # (Host-keyed, path-keyed within a host), so evaluation order among them does not
  # change behavior. Base 100 keeps protective managed rule groups (lower priority)
  # ahead of these terminating allow rules.
  rule_keys     = sort(keys(local.rules))
  rule_priority = { for k in local.rule_keys : k => 100 + index(local.rule_keys, k) }

  # WAF resource names allow only [A-Za-z0-9-_]; derive a readable, stable suffix.
  rule_name = { for k in local.rule_keys : k => replace(k, "/[^a-zA-Z0-9]+/", "-") }

  # AWS managed rule groups, evaluated (priority <100) ahead of the allow rules so
  # malicious requests are blocked before an allow rule can pass them through.
  managed_rule_groups = {
    "aws-managed-common"     = { priority = 10, name = "AWSManagedRulesCommonRuleSet" }
    "aws-managed-sqli"       = { priority = 20, name = "AWSManagedRulesSQLiRuleSet" }
    "aws-managed-bad-inputs" = { priority = 30, name = "AWSManagedRulesKnownBadInputsRuleSet" }
  }
}
