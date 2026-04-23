# --------------------------------------------------------------------------------
# CloudWatch Alarms (dev-lenient thresholds).
# --------------------------------------------------------------------------------
# Every alarm sets `treat_missing_data = "notBreaching"` so missing data
# (e.g. no traffic) does not trigger the alarm. `evaluation_periods` are
# deliberately longer than the metric period to smooth over deploy blips
# (see terraform-conventions §10 ECS healthCheck note).

# --------------------------------------------------------------------------------
# WARNING: ALB target 5xx spike (per lane)
# --------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  for_each = var.lanes

  alarm_name          = "${var.project_name}-${var.environment}-${each.value}-alb-5xx"
  alarm_description   = "ALB ${each.value} target 5xx count exceeded threshold — likely app error"
  alarm_actions       = [aws_sns_topic.alert["warning"].arn]
  ok_actions          = [aws_sns_topic.alert["warning"].arn]
  treat_missing_data  = "notBreaching"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = var.alb_arn_suffixes[each.value] }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.thresholds.alb_5xx_count
  comparison_operator = "GreaterThanOrEqualToThreshold"

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.value}-alb-5xx"
  }
}

# --------------------------------------------------------------------------------
# WARNING: Aurora CPU high
# --------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "aurora_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-aurora-cpu"
  alarm_description   = "Aurora CPU utilization sustained high — consider capacity tune or query tuning"
  alarm_actions       = [aws_sns_topic.alert["warning"].arn]
  ok_actions          = [aws_sns_topic.alert["warning"].arn]
  treat_missing_data  = "notBreaching"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBClusterIdentifier = var.aurora_cluster_identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.thresholds.aurora_cpu_percent
  comparison_operator = "GreaterThanOrEqualToThreshold"

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-cpu"
  }
}

# --------------------------------------------------------------------------------
# WARNING: Aurora connections nearing capacity
# --------------------------------------------------------------------------------
# 0.5 ACU Aurora Serverless v2 has max_connections ≈ 45, so 40 leaves
# headroom for a backend restart before saturation.

resource "aws_cloudwatch_metric_alarm" "aurora_connections" {
  alarm_name          = "${var.project_name}-${var.environment}-aurora-connections"
  alarm_description   = "Aurora DB connection count approaching max_connections for current ACU"
  alarm_actions       = [aws_sns_topic.alert["warning"].arn]
  ok_actions          = [aws_sns_topic.alert["warning"].arn]
  treat_missing_data  = "notBreaching"
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  dimensions          = { DBClusterIdentifier = var.aurora_cluster_identifier }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.thresholds.aurora_connections
  comparison_operator = "GreaterThanOrEqualToThreshold"

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-connections"
  }
}

# --------------------------------------------------------------------------------
# CRITICAL: ECS running count below desired
# --------------------------------------------------------------------------------
# evaluation_periods tuned by var so that short deploy blips don't fire.

resource "aws_cloudwatch_metric_alarm" "ecs_running_gap" {
  for_each = var.ecs_service_names

  alarm_name          = "${var.project_name}-${var.environment}-${each.key}-running-gap"
  alarm_description   = "ECS service ${each.key} has fewer running tasks than desired for extended period"
  alarm_actions       = [aws_sns_topic.alert["critical"].arn]
  ok_actions          = [aws_sns_topic.alert["critical"].arn]
  treat_missing_data  = "notBreaching"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = var.thresholds.ecs_running_gap_evaluations

  metric_query {
    id          = "gap"
    expression  = "desired - running"
    label       = "Desired minus Running"
    return_data = true
  }

  metric_query {
    id = "desired"
    metric {
      namespace   = "ECS/ContainerInsights"
      metric_name = "DesiredTaskCount"
      dimensions = {
        ClusterName = var.ecs_cluster_name
        ServiceName = each.value
      }
      period = 60
      stat   = "Maximum"
    }
  }

  metric_query {
    id = "running"
    metric {
      namespace   = "ECS/ContainerInsights"
      metric_name = "RunningTaskCount"
      dimensions = {
        ClusterName = var.ecs_cluster_name
        ServiceName = each.value
      }
      period = 60
      stat   = "Minimum"
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}-running-gap"
  }
}

# --------------------------------------------------------------------------------
# CRITICAL: ALB target group healthy host count zero (per lane)
# --------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "alb_healthy_host" {
  for_each = var.lanes

  alarm_name         = "${var.project_name}-${var.environment}-${each.value}-healthy-host-zero"
  alarm_description  = "ALB ${each.value} target group has 0 healthy hosts — all tasks unhealthy"
  alarm_actions      = [aws_sns_topic.alert["critical"].arn]
  ok_actions         = [aws_sns_topic.alert["critical"].arn]
  treat_missing_data = "notBreaching"
  namespace          = "AWS/ApplicationELB"
  metric_name        = "HealthyHostCount"
  dimensions = {
    LoadBalancer = var.alb_arn_suffixes[each.value]
    TargetGroup  = var.target_group_arn_suffixes[each.value]
  }
  statistic           = "Minimum"
  period              = 120
  evaluation_periods  = var.thresholds.alb_healthy_host_evaluations
  threshold           = 1
  comparison_operator = "LessThanThreshold"

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.value}-healthy-host-zero"
  }
}

# --------------------------------------------------------------------------------
# CRITICAL: Firehose delivery to S3 failures
# --------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "firehose_delivery_failure" {
  for_each = var.firehose_stream_names

  alarm_name          = "${var.project_name}-${var.environment}-firehose-${each.key}-failure"
  alarm_description   = "Firehose ${each.key} stream failed to deliver records to S3 — audit/log data at risk"
  alarm_actions       = [aws_sns_topic.alert["critical"].arn]
  ok_actions          = [aws_sns_topic.alert["critical"].arn]
  treat_missing_data  = "notBreaching"
  namespace           = "AWS/Firehose"
  metric_name         = "DeliveryToS3.Records"
  dimensions          = { DeliveryStreamName = each.value }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"

  tags = {
    Name = "${var.project_name}-${var.environment}-firehose-${each.key}-failure"
  }
}
