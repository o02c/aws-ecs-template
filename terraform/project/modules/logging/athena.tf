# --------------------------------------------------------------------------------
# Glue Database (Athena catalog)
# --------------------------------------------------------------------------------
# Athena tables defined in `athena/*.sql` register themselves into this database.
# Keeping the database here (Terraform-managed) gives the SQL files a stable name
# to target across environments without templating.

resource "aws_glue_catalog_database" "logs" {
  name        = "${replace(var.project_name, "-", "_")}_${var.environment}_logs"
  description = "Database for access-log Athena tables (CloudFront, ALB, S3, WAF)"
}

# --------------------------------------------------------------------------------
# Athena Workgroup
# --------------------------------------------------------------------------------
# Enforcing the result location via workgroup means analysts cannot accidentally
# fan results out to a personal bucket — every query writes back here, under the
# bucket's lifecycle policy. `enforce_workgroup_configuration = true` is what
# binds the override.

resource "aws_athena_workgroup" "logs" {
  name        = "${var.project_name}-${var.environment}-logs"
  description = "Workgroup for ad-hoc access-log analysis"
  state       = "ENABLED"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.id}/workgroup/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-logs"
  }
}
