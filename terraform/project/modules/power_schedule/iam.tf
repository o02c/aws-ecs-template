locals {
  db_enabled     = var.schedule.db.stop.enabled || var.schedule.db.start.enabled
  ecs_enabled    = var.schedule.ecs.stop.enabled || var.schedule.ecs.start.enabled
  alarms_enabled = var.schedule.alarms.stop.enabled || var.schedule.alarms.start.enabled

  db_actions = compact([
    var.schedule.db.stop.enabled ? "rds:StopDBCluster" : "",
    var.schedule.db.start.enabled ? "rds:StartDBCluster" : "",
  ])
  alarm_actions = compact([
    var.schedule.alarms.stop.enabled ? "cloudwatch:DisableAlarmActions" : "",
    var.schedule.alarms.start.enabled ? "cloudwatch:EnableAlarmActions" : "",
  ])
}

# --------------------------------------------------------------------------------
# Scheduler Execution Role
# --------------------------------------------------------------------------------

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_account_id]
    }

    # Confused-deputy guard: only schedules in this module's own group may
    # assume the role (it can stop the DB and scale ECS to 0). Scoped to the
    # group name (no resource ref to the schedules themselves, so no cycle).
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:scheduler:${var.aws_region}:${var.aws_account_id}:schedule/${aws_scheduler_schedule_group.this.name}/*"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.project_name}-${var.environment}-power-schedule"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "this" {
  dynamic "statement" {
    for_each = local.db_enabled ? { this = true } : {}
    content {
      sid       = "ControlAuroraCluster"
      actions   = local.db_actions
      resources = [var.db_cluster_arn]
    }
  }

  dynamic "statement" {
    for_each = local.ecs_enabled ? { this = true } : {}
    content {
      sid       = "ScaleEcsServices"
      actions   = ["ecs:UpdateService"]
      resources = local.ecs_service_arns
    }
  }

  dynamic "statement" {
    for_each = local.alarms_enabled ? { this = true } : {}
    content {
      sid       = "ToggleAlarmActions"
      actions   = local.alarm_actions
      resources = values(var.alarm_arns)
    }
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "${var.project_name}-${var.environment}-power-schedule"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.this.json
}
