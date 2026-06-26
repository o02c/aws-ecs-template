variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "kvs_arn" {
  description = "ARN of the CloudFront KeyValueStore holding the maintenance flag (from the cdn module)"
  type        = string
}

variable "kvs_key" {
  description = "Key toggled in the KeyValueStore. Must match the key read by the viewer-request function."
  type        = string
  default     = "maintenance"
}

variable "logs_kms_key_arn" {
  description = "KMS key ARN for CloudWatch Logs encryption"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the state machine log group"
  type        = number
  default     = 30
}

variable "schedule" {
  description = <<-EOT
    Maintenance window schedule. `on` turns the gate on (start of the window),
    `off` turns it off. Each toggles independently. cron uses EventBridge
    Scheduler syntax, evaluated in `timezone`.
  EOT
  type = object({
    timezone = string
    on       = object({ enabled = bool, cron = string })
    off      = object({ enabled = bool, cron = string })
  })
}
