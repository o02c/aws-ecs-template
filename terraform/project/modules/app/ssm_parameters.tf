# --------------------------------------------------------------------------------
# SSM Parameter Store (application secrets)
# --------------------------------------------------------------------------------

resource "aws_ssm_parameter" "django_secret_key" {
  for_each = var.services

  name  = "/${var.project_name}/${var.environment}/${each.key}/django-secret-key"
  type  = "SecureString"
  value = "change-me"

  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}-django-secret-key"
  }
}
