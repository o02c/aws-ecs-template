# --------------------------------------------------------------------------------
# ECS Task Execution Role (shared)
# --------------------------------------------------------------------------------

resource "aws_iam_role" "task_execution" {
  name = "${var.project_name}-${var.environment}-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-task-execution"
  }
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Pull-through cache requires additional ECR permissions on execution role
# ref: https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.html#pull-through-cache-iam
resource "aws_iam_role_policy" "task_execution_pull_through_cache" {
  name = "ecr-pull-through-cache"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository",
          "ecr:BatchImportUpstreamImage"
        ]
        Resource = "arn:aws:ecr:*:${var.aws_account_id}:repository/${aws_ecr_pull_through_cache_rule.ecr_public.ecr_repository_prefix}/*"
      }
    ]
  })
}

# SSM Parameter Store access for ECS task execution role (secrets injection)
resource "aws_iam_role_policy" "task_execution_ssm" {
  name = "ssm-parameter-access"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameters",
          "ssm:GetParameter"
        ]
        Resource = [for name, param in aws_ssm_parameter.django_secret_key : param.arn]
      },
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = var.logs_kms_key_arn
      }
    ]
  })
}

# --------------------------------------------------------------------------------
# ECS Task Roles (per-service)
# --------------------------------------------------------------------------------

resource "aws_iam_role" "task" {
  for_each = var.services

  name = "${var.project_name}-${var.environment}-${each.key}-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}-task"
  }
}

# Attach RDS IAM auth policy to task roles
resource "aws_iam_role_policy_attachment" "task_rds_auth" {
  for_each = var.services

  role       = aws_iam_role.task[each.key].name
  policy_arn = var.rds_iam_auth_policy_arn
}

# Attach S3 access policy to task roles
resource "aws_iam_role_policy_attachment" "task_s3_access" {
  for_each = var.services

  role       = aws_iam_role.task[each.key].name
  policy_arn = var.s3_access_policy_arns[each.value.lane]
}

# --------------------------------------------------------------------------------
# App Resources Bucket: per-service inline policy (lane-scoped read access)
# --------------------------------------------------------------------------------
# Each task role gets an inline policy limiting object reads to common/* (shared)
# and <lane>/* (lane-private). ListBucket is gated by s3:prefix so one lane
# cannot enumerate another lane's keys.

resource "aws_iam_role_policy" "task_app_resources" {
  for_each = var.services

  name = "app-resources-access"
  role = aws_iam_role.task[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadLaneScopedObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
        ]
        Resource = [
          "${aws_s3_bucket.app_resources.arn}/common/*",
          "${aws_s3_bucket.app_resources.arn}/${each.value.lane}/*",
        ]
      },
      {
        Sid      = "ListLaneScopedPrefixes"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.app_resources.arn
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "",
              "common",
              "common/*",
              each.value.lane,
              "${each.value.lane}/*",
            ]
          }
        }
      },
      {
        # SSE-KMS objects require kms:Decrypt to unwrap the data key on read.
        # Scoped to the project s3 key, not wildcard.
        Sid      = "DecryptObjectEnvelope"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = var.s3_kms_key_arn
      },
    ]
  })
}

# --------------------------------------------------------------------------------
# FireLens Permissions (Firehose only; ECS task stdout/stderr はすべて Firehose 経由)
# --------------------------------------------------------------------------------

resource "aws_iam_role_policy" "task_firelens" {
  for_each = var.services

  name = "firelens-access"
  role = aws_iam_role.task[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "firehose:PutRecordBatch"
        Resource = [for s in aws_kinesis_firehose_delivery_stream.this : s.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::${var.log_bucket_id}",
          "arn:aws:s3:::${var.log_bucket_id}/fluent-bit/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = var.s3_kms_key_arn
      }
    ]
  })
}

# --------------------------------------------------------------------------------
# Firehose delivery role (writes FireLens-routed ECS logs to the shared log bucket)
# --------------------------------------------------------------------------------

resource "aws_iam_role" "firehose" {
  name = "${var.project_name}-${var.environment}-firehose"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-firehose"
  }
}

resource "aws_iam_role_policy" "firehose" {
  name = "firehose-s3-access"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject",
        ]
        Resource = concat(
          ["arn:aws:s3:::${var.log_bucket_id}"],
          [for k, v in local.firehose_streams : "arn:aws:s3:::${var.log_bucket_id}/${v.s3_prefix}/*"],
          [for k, v in local.firehose_streams : "arn:aws:s3:::${var.log_bucket_id}/${v.s3_prefix}-errors/*"],
        )
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
        ]
        Resource = var.s3_kms_key_arn
      }
    ]
  })
}

# --------------------------------------------------------------------------------
# Secrets Manager Access (for CloudFront signing key, feature-flagged)
# --------------------------------------------------------------------------------

resource "aws_iam_policy" "secrets_read" {
  for_each = var.cloudfront_signing_enabled ? { "default" = true } : {}

  name = "${var.project_name}-${var.environment}-secrets-read"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadSigningSecret"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = var.cloudfront_signing_key_secret_arn
      },
      {
        # Secrets Manager wraps the secret value with the secrets KMS key;
        # GetSecretValue fails without kms:Decrypt on that key.
        Sid      = "DecryptSigningSecretEnvelope"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = var.secrets_kms_key_arn
      },
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-secrets-read"
  }
}

resource "aws_iam_role_policy_attachment" "task_secrets_read" {
  for_each = var.cloudfront_signing_enabled ? var.services : {}

  role       = aws_iam_role.task[each.key].name
  policy_arn = aws_iam_policy.secrets_read["default"].arn
}

# --------------------------------------------------------------------------------
# SES Send Policy Attachment (feature-flagged)
# --------------------------------------------------------------------------------
# When the email module is disabled, email_policy_arn == "" and no attachment
# is created. The email module itself owns the policy (scoped to the SES
# domain identity) — we only attach it to each task role here.

resource "aws_iam_role_policy_attachment" "task_email" {
  # email_enabled is a plan-time bool so for_each is known at plan time.
  # policy_arn itself may be known only after apply (module.email output).
  for_each = var.email_enabled ? var.services : {}

  role       = aws_iam_role.task[each.key].name
  policy_arn = var.email_policy_arn
}
