# --------------------------------------------------------------------------------
# Maintenance toggle state machine
# --------------------------------------------------------------------------------
# Flips the KeyValueStore `maintenance` flag. PutKey is optimistic-locked, so the
# machine reads the current ETag (DescribeKeyValueStore) then writes (PutKey).
#
# The KVS data plane is signed with SigV4A; Step Functions' AWS SDK integration
# handles that internally, so no Lambda (and no bundled signer / build step) is
# needed. Invoked by EventBridge Scheduler with { "value": "on" | "off" }.

resource "aws_sfn_state_machine" "toggle" {
  name     = "${var.project_name}-${var.environment}-maintenance-toggle"
  role_arn = aws_iam_role.sfn.arn
  type     = "STANDARD"

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  # SFn validates the role can write to the log destination at create/update time;
  # attach the logging policy first (the role_arn ref alone doesn't order this).
  depends_on = [aws_iam_role_policy.sfn]

  definition = jsonencode({
    Comment = "Toggle CloudFront KeyValueStore maintenance flag. Input: { value: on|off }"
    StartAt = "Describe"
    States = {
      Describe = {
        Type       = "Task"
        Resource   = "arn:aws:states:::aws-sdk:cloudfrontkeyvaluestore:describeKeyValueStore"
        Parameters = { KvsARN = var.kvs_arn }
        ResultPath = "$.kvs"
        Next       = "PutKey"
      }
      PutKey = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:cloudfrontkeyvaluestore:putKey"
        Parameters = {
          KvsARN      = var.kvs_arn
          Key         = var.kvs_key
          "Value.$"   = "$.value"
          "IfMatch.$" = "$.kvs.ETag"
        }
        End = true
      }
    }
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-maintenance-toggle"
  }
}
