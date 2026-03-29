# --------------------------------------------------------------------------------
# IAM Groups
# --------------------------------------------------------------------------------

resource "aws_iam_group" "this" {
  for_each = var.groups

  name = each.key
  path = each.value.path
}

resource "aws_iam_group_policy_attachment" "this" {
  for_each = {
    for pair in flatten([
      for group_name, group in var.groups : [
        for policy_arn in group.policy_arns : {
          key        = "${group_name}-${policy_arn}"
          group_name = group_name
          policy_arn = policy_arn
        }
      ]
    ]) : pair.key => pair
  }

  group      = aws_iam_group.this[each.value.group_name].name
  policy_arn = each.value.policy_arn
}
