# --------------------------------------------------------------------------------
# Amazon Inspector
# --------------------------------------------------------------------------------

data "aws_caller_identity" "this" {}

resource "aws_inspector2_enabler" "this" {
  account_ids    = [data.aws_caller_identity.this.account_id]
  resource_types = ["ECR", "LAMBDA"]
}
