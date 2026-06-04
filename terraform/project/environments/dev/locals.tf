locals {
  aws_region  = "ap-northeast-1"
  vpc_cidr    = var.vpc_cidr
  name_prefix = "${var.project_name}-${var.environment}"

  # CloudFront static-assets cache TTL
  cache_ttl = {
    default_seconds = 86400    # 1 day
    max_seconds     = 31536000 # 1 year
  }

  # Firehose audit-log delivery buffering
  firehose_buffering_interval_seconds = 60

  # --------------------------------------------------------------------------------
  # Log retention / lifecycle (single source of truth)
  # --------------------------------------------------------------------------------
  # 全ログ種別の出力先・retention・storage class transition・expiration を一元管理。
  # destinations.cloudwatch / destinations.s3 で個別に経路を on/off 可能。
  # 長期 (10y+) 保持を見据え、Standard-IA(30d) → Glacier IR(90d) → Glacier(180d) →
  # Deep Archive(365d) の 4 段階遷移を基本形とする。expiration_days = null は
  # 「削除しない」を意味する。
  #
  # 注意:
  #   * STANDARD_IA は最低 30 日、GLACIER_* 系は最低 90 日同一クラス保持の制約あり
  #   * GLACIER_IR / GLACIER / DEEP_ARCHIVE オブジェクトは Athena 直クエリ不可
  #     (restore 必要)。Athena 検索要件のあるログは IA 期間を伸ばすこと
  #   * Object Lock の on/off は log_buckets で別管理

  long_term_storage_class = "DEEP_ARCHIVE" # GLACIER に切替可。長期段の storage_class を統一管理

  log_retention = {
    audit = {
      destinations = { cloudwatch = false, s3 = true }
      s3 = {
        bucket = "access_logs"
        prefix = "audit/"
        transitions = [
          { days = 30, storage_class = "STANDARD_IA" },
          { days = 90, storage_class = "GLACIER_IR" },
          { days = 180, storage_class = "GLACIER" },
          { days = 365, storage_class = local.long_term_storage_class },
        ]
        expiration_days = null
      }
    }
    ecs_logs_app = {
      destinations = { cloudwatch = false, s3 = true }
      s3 = {
        bucket = "access_logs"
        prefix = "ecs-logs-app/"
        transitions = [
          { days = 90, storage_class = "GLACIER_IR" },
          { days = 365, storage_class = local.long_term_storage_class },
        ]
        expiration_days = 1825 # 5y
      }
    }
    ecs_logs_nginx = {
      destinations = { cloudwatch = false, s3 = true }
      s3 = {
        bucket = "access_logs"
        prefix = "ecs-logs-nginx/"
        transitions = [
          { days = 90, storage_class = "GLACIER_IR" },
          { days = 365, storage_class = local.long_term_storage_class },
        ]
        expiration_days = 1825 # 5y
      }
    }
    vpc_flow = {
      destinations = { cloudwatch = false, s3 = true }
      s3 = {
        bucket = "access_logs"
        prefix = "vpc-flow/"
        transitions = [
          { days = 30, storage_class = "STANDARD_IA" },
          { days = 90, storage_class = "GLACIER_IR" },
          { days = 365, storage_class = local.long_term_storage_class },
        ]
        expiration_days = 1095 # 3y
      }
    }
    alb_access = {
      destinations = { cloudwatch = false, s3 = true }
      s3 = {
        bucket = "access_logs"
        prefix = "alb/"
        transitions = [
          { days = 30, storage_class = "STANDARD_IA" },
          { days = 90, storage_class = "GLACIER_IR" },
          { days = 365, storage_class = local.long_term_storage_class },
        ]
        expiration_days = 1095
      }
    }
    cloudfront_access = {
      destinations = { cloudwatch = false, s3 = true }
      s3 = {
        bucket = "access_logs"
        prefix = "cloudfront/"
        transitions = [
          { days = 30, storage_class = "STANDARD_IA" },
          { days = 90, storage_class = "GLACIER_IR" },
          { days = 365, storage_class = local.long_term_storage_class },
        ]
        expiration_days = 1095
      }
    }
    s3_access = {
      destinations = { cloudwatch = false, s3 = true }
      s3 = {
        bucket = "access_logs"
        prefix = "s3/"
        transitions = [
          { days = 30, storage_class = "STANDARD_IA" },
          { days = 90, storage_class = "GLACIER_IR" },
          { days = 365, storage_class = local.long_term_storage_class },
        ]
        expiration_days = 1095
      }
    }
    waf = {
      destinations = { cloudwatch = false, s3 = true }
      s3 = {
        bucket = "waf_logs"
        prefix = ""
        transitions = [
          { days = 30, storage_class = "STANDARD_IA" },
          { days = 90, storage_class = "GLACIER_IR" },
          { days = 180, storage_class = "GLACIER" },
          { days = 365, storage_class = local.long_term_storage_class },
        ]
        expiration_days = null
      }
    }
    fluent_bit = {
      destinations = { cloudwatch = true, s3 = false }
      cloudwatch = {
        retention_days = 7
        log_class      = "INFREQUENT_ACCESS"
      }
    }
  }

  # --------------------------------------------------------------------------------
  # Log bucket Object Lock (WORM)
  # --------------------------------------------------------------------------------
  # enabled = true はバケット作成時のみ設定可能 (不可逆)。既存バケットを on に切替
  # する場合は recreate (= データ移行) が必要。default_retention をセットすると
  # バケット内 **全 object** に retention が適用される (prefix 単位の default は不可)。
  log_buckets = {
    access_logs = {
      object_lock = {
        enabled           = false
        default_retention = null
        # 例: { mode = "COMPLIANCE", days = 3650 }
      }
    }
    waf_logs = {
      object_lock = {
        enabled           = false
        default_retention = null
      }
    }
  }

  # ALB idle timeout (connection keep-alive budget)
  alb_idle_timeout_seconds = 60

  # ALB target group tuning
  lb_target_group = {
    deregistration_delay_seconds = 30
    health_check = {
      path                = "/health"
      healthy_threshold   = 2
      unhealthy_threshold = 3
      timeout_seconds     = 5
      interval_seconds    = 30
    }
  }

  # Container port (ECS → ALB target group)
  container_port = 8081

  # CloudFront WAF rate limit (requests per 5-min per IP)
  waf_rate_limit = 2000

  # CloudFront geo restriction (ISO 3166-1 alpha-2 whitelist)
  geo_restriction_locations = ["JP"]

  # Signed URL path pattern (for CloudFront signing feature)
  signed_files_path_pattern = "/files/*"

  # Email (SES sandbox). Set enabled = false to skip all SES / Route53 records.
  # After apply, verify_recipients receive a confirmation email from AWS that
  # must be clicked manually in Gmail. The domain DKIM is auto-verified.
  email = {
    enabled             = true
    sender_address      = "no-reply@oo2cc.click"
    mail_from_subdomain = "bounce"
    verified_recipients = ["ohtsuka.kentaro.o2c@gmail.com"]
    dmarc_rua_address   = "postmaster@oo2cc.click"
  }

  # CloudWatch Alarm → SNS → Email
  # Recipients must confirm the SNS subscription email from AWS (Gmail manual click).
  alarm_recipients = ["ohtsuka.kentaro.o2c@gmail.com"]

  alarm_thresholds = {
    alb_5xx_count                = 5
    aurora_cpu_percent           = 80
    aurora_connections           = 40
    ecs_running_gap_evaluations  = 5 # 1min × 5 = 5min sustained
    alb_healthy_host_evaluations = 5 # 2min × 5 = 10min sustained
  }

  # Aurora PostgreSQL cluster config. Change these to tune per env.
  # Provisioned instances (Django の永続コネクション + ECS Fargate の steady load
  # に Serverless v2 が合わないため、t4g.medium ベースの provisioned に統一)。
  db_config = {
    engine_version          = "16.4"
    database_name           = "app"
    iam_username            = "app"
    instance_class          = "db.t4g.medium"
    instances               = { writer = {}, reader = {} }
    backup_retention_period = 7
    deletion_protection     = false
    skip_final_snapshot     = true
    # Enhanced Monitoring: OS-level metrics (process list, per-device I/O, memory)
    # to CloudWatch Logs every N seconds. 60 is the low-cost default; drop to
    # 15/5/1 for finer resolution at higher CloudWatch Logs cost.
    monitoring_interval = 60
  }

  # db_sql Lambda. master_username (db_config 経由) は DDL Lambda が利用。
  # DML Lambda は IAM 認証で dml_username に接続するため、初回のみ DDL Lambda 経由で
  # `CREATE ROLE <dml_username> LOGIN; GRANT rds_iam TO <dml_username>;` 等の bootstrap が必要。
  db_sql = {
    dml_username       = "app_rw"
    log_retention_days = 30
  }

  # KMS keys managed at the project state layer. Used by Aurora / S3 / CloudWatch /
  # Secrets Manager for this project. shared 側と同名 key (logs) があっても、
  # それぞれ別の state で別の resource 群を暗号化している（§8）。
  kms_keys = {
    rds = {
      description = "CMK for Aurora encryption"
      service     = null
    }
    s3 = {
      description        = "CMK for S3 bucket encryption"
      service            = null
      cloudfront_enabled = true
    }
    logs = {
      description = "CMK for CloudWatch Logs encryption"
      service     = "logs.${local.aws_region}.amazonaws.com"
    }
    secrets = {
      description = "CMK for Secrets Manager encryption"
      service     = null
    }
    ecr = {
      description = "CMK for ECR repository encryption"
      service     = null
    }
    sns = {
      description = "CMK for SNS topic encryption (CloudWatch Alarm publishes)"
      service     = "cloudwatch.amazonaws.com"
    }
  }

  # All lanes share a single apex domain; CloudFront picks the lane by path.
  # Exactly one lane must have an empty path_prefix (it serves the default behavior).
  # API endpoints live at ${path_prefix}/api/*; static assets at ${path_prefix}*.
  lanes = {
    user  = { path_prefix = "" }
    admin = { path_prefix = "/admin" }
  }

  # WAF IP allowlist. scope = "admin" gates only the non-default lane's path
  # (e.g. /admin*); "global" gates every request. Empty allowed_cidrs disables.
  ip_allowlist = {
    scope         = "admin"
    allowed_cidrs = []
  }

  azs = ["${local.aws_region}a", "${local.aws_region}c"]

  private_subnets = {
    "${local.aws_region}a" = cidrsubnet(local.vpc_cidr, 8, 11)
    "${local.aws_region}c" = cidrsubnet(local.vpc_cidr, 8, 12)
  }

  security_groups = toset(concat(
    ["ecs", "db", "db-sql"],
    [for lane in keys(local.lanes) : "${lane}-alb"]
  ))

  # S3 gateway endpoint retained (free, better performance)
  gateway_endpoints = {
    s3 = "com.amazonaws.${local.aws_region}.s3"
  }

  # Transit Gateway ID from shared state
  transit_gateway_id = data.terraform_remote_state.shared.outputs.transit_gateway_id

  services = {
    user-api  = { lane = "user" }
    admin-api = { lane = "admin" }
  }
}
