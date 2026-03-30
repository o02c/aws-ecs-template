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

resource "aws_iam_user_group_membership" "this" {
  for_each = { for name, user in var.users : name => user if length(user.groups) > 0 }

  user   = aws_iam_user.this[each.key].name
  groups = [for g in each.value.groups : aws_iam_group.this[g].name]
}
