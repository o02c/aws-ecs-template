locals {
  # One schedule per enabled action, each carrying the value to PutKey.
  schedules = merge(
    var.schedule.on.enabled ? { on = { cron = var.schedule.on.cron, value = "on" } } : {},
    var.schedule.off.enabled ? { off = { cron = var.schedule.off.cron, value = "off" } } : {},
  )
}

# --------------------------------------------------------------------------------
# EventBridge Scheduler
# --------------------------------------------------------------------------------

resource "aws_scheduler_schedule_group" "this" {
  name = "${var.project_name}-${var.environment}-maintenance"

  tags = {
    Name = "${var.project_name}-${var.environment}-maintenance"
  }
}

resource "aws_scheduler_schedule" "this" {
  for_each = local.schedules

  name       = "${var.project_name}-${var.environment}-maintenance-${each.key}"
  group_name = aws_scheduler_schedule_group.this.name

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = each.value.cron
  schedule_expression_timezone = var.schedule.timezone

  target {
    arn      = aws_sfn_state_machine.toggle.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ value = each.value.value })
  }
}
