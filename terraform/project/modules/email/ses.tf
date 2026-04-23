# --------------------------------------------------------------------------------
# SES Domain Identity + DKIM + MAIL FROM
# --------------------------------------------------------------------------------
# DKIM tokens are published as CNAME records (see route53.tf). The custom
# MAIL FROM subdomain provides alignment for DMARC so receivers see
# `bounce.<domain>` instead of amazonses.com as the Return-Path.

resource "aws_ses_domain_identity" "this" {
  domain = var.domain_name
}

resource "aws_ses_domain_dkim" "this" {
  domain = aws_ses_domain_identity.this.domain
}

resource "aws_ses_domain_mail_from" "this" {
  domain           = aws_ses_domain_identity.this.domain
  mail_from_domain = "${var.mail_from_subdomain}.${var.domain_name}"

  # Reject: if MAIL FROM records (MX/TXT) are missing, drop the bounce instead
  # of silently falling back to amazonses.com.
  behavior_on_mx_failure = "RejectMessage"
}

# --------------------------------------------------------------------------------
# Verified Recipients (SES sandbox)
# --------------------------------------------------------------------------------
# `aws_ses_email_identity` only requests verification — the recipient must
# manually click the confirmation link in the email AWS sends to them.
# Until confirmed, sending to this address fails with a sandbox error.

resource "aws_ses_email_identity" "recipient" {
  for_each = toset(var.verified_recipients)

  email = each.value
}
