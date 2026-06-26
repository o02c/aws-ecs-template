locals {
  # ECS services are ecspresso-managed, so no Terraform attribute exposes their
  # ARNs. Construct them from cluster + service name to scope IAM to the exact
  # services (avoids a cluster-wide service/* wildcard).
  ecs_service_arns = [
    for svc in var.ecs_service_names :
    "arn:aws:ecs:${var.aws_region}:${var.aws_account_id}:service/${var.ecs_cluster_name}/${svc}"
  ]

  # Aurora: one schedule per enabled action (StopDBCluster / StartDBCluster).
  db_schedules = {
    for act, cfg in { stop = var.schedule.db.stop, start = var.schedule.db.start } :
    "db-${act}" => {
      cron       = cfg.cron
      target_arn = "arn:aws:scheduler:::aws-sdk:rds:${act == "stop" ? "stopDBCluster" : "startDBCluster"}"
      input      = jsonencode({ DbClusterIdentifier = var.db_cluster_identifier })
    } if cfg.enabled
  }

  # Alarms: one schedule per enabled action, toggling actions for every alarm.
  alarm_schedules = {
    for act, cfg in { stop = var.schedule.alarms.stop, start = var.schedule.alarms.start } :
    "alarms-${act}" => {
      cron       = cfg.cron
      target_arn = "arn:aws:scheduler:::aws-sdk:cloudwatch:${act == "stop" ? "disableAlarmActions" : "enableAlarmActions"}"
      input      = jsonencode({ AlarmNames = keys(var.alarm_arns) })
    } if cfg.enabled
  }

  # ECS: UpdateService acts on a single service, so fan out per service. stop and
  # start carry different desired counts, so they are built separately.
  ecs_schedules = merge(
    var.schedule.ecs.stop.enabled ? {
      for svc in var.ecs_service_names : "ecs-${svc}-stop" => {
        cron       = var.schedule.ecs.stop.cron
        target_arn = "arn:aws:scheduler:::aws-sdk:ecs:updateService"
        input      = jsonencode({ Cluster = var.ecs_cluster_name, Service = svc, DesiredCount = 0 })
      }
    } : {},
    var.schedule.ecs.start.enabled ? {
      for svc in var.ecs_service_names : "ecs-${svc}-start" => {
        cron       = var.schedule.ecs.start.cron
        target_arn = "arn:aws:scheduler:::aws-sdk:ecs:updateService"
        input      = jsonencode({ Cluster = var.ecs_cluster_name, Service = svc, DesiredCount = var.schedule.ecs.start.desired_count })
      }
    } : {},
  )

  schedules = merge(local.db_schedules, local.alarm_schedules, local.ecs_schedules)
}

# --------------------------------------------------------------------------------
# EventBridge Scheduler
# --------------------------------------------------------------------------------

resource "aws_scheduler_schedule_group" "this" {
  name = "${var.project_name}-${var.environment}-power"

  tags = {
    Name = "${var.project_name}-${var.environment}-power"
  }
}

resource "aws_scheduler_schedule" "this" {
  for_each = local.schedules

  name       = "${var.project_name}-${var.environment}-${each.key}"
  group_name = aws_scheduler_schedule_group.this.name

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = each.value.cron
  schedule_expression_timezone = var.schedule.timezone

  target {
    arn      = each.value.target_arn
    role_arn = aws_iam_role.this.arn
    input    = each.value.input
  }
}
