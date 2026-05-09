# --------------------------------------------------------------------------------
# Amazon Inspector
# --------------------------------------------------------------------------------

resource "aws_inspector2_enabler" "this" {
  account_ids    = [var.aws_account_id]
  resource_types = ["ECR"]
}
