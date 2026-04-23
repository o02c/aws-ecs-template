# --------------------------------------------------------------------------------
# VPC Flow Logs
# --------------------------------------------------------------------------------

resource "aws_flow_log" "this" {
  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_cloudwatch_log_group.flow_log.arn

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }
}
