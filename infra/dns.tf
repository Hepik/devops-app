resource "aws_acm_certificate" "main" {
  domain_name       = "${var.subdomain}.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# ACM won't issue the cert until it sees this exact CNAME published at your
# DNS provider — proof you control the domain. Since the domain isn't in
# Route 53, Terraform can't create this record for you; these outputs are
# what you paste into your registrar's DNS panel by hand.
output "acm_validation_record_name" {
  description = "DNS record NAME to create at your registrar (CNAME) — proves domain ownership to ACM"
  value       = tolist(aws_acm_certificate.main.domain_validation_options)[0].resource_record_name
}

output "acm_validation_record_value" {
  description = "DNS record VALUE for the same CNAME"
  value       = tolist(aws_acm_certificate.main.domain_validation_options)[0].resource_record_value
}

# This resource actively WAITS (polls) until ACM confirms the validation
# CNAME is visible — it will hang/timeout on the very first apply, before
# you've had a chance to create that record anywhere. That's why this step
# is applied on its own (see README), separately from everything that
# depends on it (the HTTPS listener below).
resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [aws_acm_certificate.main.domain_validation_options.*.resource_record_name[0]]
}
