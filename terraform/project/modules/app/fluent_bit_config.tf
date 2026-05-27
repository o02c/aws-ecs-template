# --------------------------------------------------------------------------------
# Fluent Bit Config (S3)
# --------------------------------------------------------------------------------
# Uploaded to the shared access-log bucket so the FireLens init process can
# fetch it at container startup.
# ref: https://github.com/aws/aws-for-fluent-bit/blob/mainline/use_cases/init-process-for-fluent-bit/README.md

resource "aws_s3_object" "fluent_bit_config" {
  bucket       = var.log_bucket_id
  key          = "fluent-bit/extra.conf"
  source       = "${path.module}/files/fluent-bit-extra.conf"
  etag         = filemd5("${path.module}/files/fluent-bit-extra.conf")
  content_type = "text/plain"
}

# Optional parsers (python_json, nginx_json, nginx). Registered with Fluent Bit
# at startup but unused unless a FILTER in fluent-bit-extra.conf references one
# by name — see the file's header for opt-in instructions.
resource "aws_s3_object" "fluent_bit_parsers" {
  bucket       = var.log_bucket_id
  key          = "fluent-bit/parsers.conf"
  source       = "${path.module}/files/fluent-bit-parsers.conf"
  etag         = filemd5("${path.module}/files/fluent-bit-parsers.conf")
  content_type = "text/plain"
}
