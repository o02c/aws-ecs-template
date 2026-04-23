# --------------------------------------------------------------------------------
# DNS records for SES (DKIM / SPF / DMARC / MAIL FROM)
# --------------------------------------------------------------------------------

# DKIM: 3 CNAME records from the domain DKIM tokens
resource "aws_route53_record" "dkim" {
  count = 3

  zone_id = var.route53_zone_id
  name    = "${aws_ses_domain_dkim.this.dkim_tokens[count.index]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 1800
  records = ["${aws_ses_domain_dkim.this.dkim_tokens[count.index]}.dkim.amazonses.com"]
}

# SPF: authorize amazonses.com to send on behalf of the domain
# -all = strict (fail unauthorized senders). Once other senders are added,
# update this TXT record to include them explicitly.
resource "aws_route53_record" "spf" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 1800
  records = ["v=spf1 include:amazonses.com -all"]
}

# DMARC: start with p=none to observe before enforcing
# Progression: p=none → p=quarantine → p=reject once delivery is stable.
resource "aws_route53_record" "dmarc" {
  zone_id = var.route53_zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 1800
  records = ["v=DMARC1; p=none; rua=mailto:${var.dmarc_rua_address}"]
}

# --------------------------------------------------------------------------------
# Custom MAIL FROM subdomain records
# --------------------------------------------------------------------------------
# The MAIL FROM domain needs its own MX (to accept bounces) and SPF TXT.

resource "aws_route53_record" "mail_from_mx" {
  zone_id = var.route53_zone_id
  name    = aws_ses_domain_mail_from.this.mail_from_domain
  type    = "MX"
  ttl     = 1800
  records = ["10 feedback-smtp.ap-northeast-1.amazonses.com"]
}

resource "aws_route53_record" "mail_from_spf" {
  zone_id = var.route53_zone_id
  name    = aws_ses_domain_mail_from.this.mail_from_domain
  type    = "TXT"
  ttl     = 1800
  records = ["v=spf1 include:amazonses.com -all"]
}
