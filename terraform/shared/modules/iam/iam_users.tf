# --------------------------------------------------------------------------------
# IAM Users
# --------------------------------------------------------------------------------

resource "aws_iam_user" "this" {
  for_each = var.users

  name = each.key
  path = each.value.path

  tags = {
    Name = each.key
  }
}

# --------------------------------------------------------------------------------
# Group Memberships
# --------------------------------------------------------------------------------

# All users are auto-enrolled in the mfa-enforced group; additional permission
# groups come from var.users[*].groups. Those group names must match
# aws_iam_group resources defined in iam_group_<name>.tf files in this module.
resource "aws_iam_user_group_membership" "this" {
  for_each = var.users

  user   = aws_iam_user.this[each.key].name
  groups = concat([aws_iam_group.mfa_enforced.name], each.value.groups)
}
