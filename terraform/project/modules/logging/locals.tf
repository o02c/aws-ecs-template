locals {
  # S3 経路を持つログ種別のみを取り出す
  s3_log_kinds = {
    for kind, cfg in var.log_retention : kind => cfg
    if cfg.destinations.s3
  }

  # バケットごとに log_kind を pivot して lifecycle rule 生成用に整形
  log_kinds_by_bucket = {
    for bucket_key in distinct([for v in values(local.s3_log_kinds) : v.s3.bucket]) :
    bucket_key => {
      for kind, cfg in local.s3_log_kinds : kind => cfg.s3
      if cfg.s3.bucket == bucket_key
    }
  }

  bucket_ids = {
    access_logs = aws_s3_bucket.access_logs.id
    waf_logs    = aws_s3_bucket.waf_logs.id
  }
}
