# --------------------------------------------------------------------------------
# Fluent Bit Config (S3)
# --------------------------------------------------------------------------------
# Uploaded to S3 for init process to download at container startup.
# ref: https://github.com/aws/aws-for-fluent-bit/blob/mainline/use_cases/init-process-for-fluent-bit/README.md

resource "aws_s3_object" "fluent_bit_config" {
  bucket       = aws_s3_bucket.audit_logs.id
  key          = "fluent-bit/extra.conf"
  source       = "${path.module}/files/fluent-bit-extra.conf"
  etag         = filemd5("${path.module}/files/fluent-bit-extra.conf")
  content_type = "text/plain"
}

# Parser definitions use the built-in /fluent-bit/parsers/parsers.conf
# referenced via aws_fluent_bit_init_file env var in the task definition.
# The init process auto-detects [PARSER] files and adds them via -R flag.
