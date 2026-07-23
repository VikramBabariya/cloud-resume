# -----------------------------------------------------------------------------
# modules/dns — Input Variables
#
# All variables are required with no default values. A missing value causes
# `terraform plan` to exit with an error before any cloud API is called.
# Requirements: 4.5, 6.6
# -----------------------------------------------------------------------------

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for the vikram-sre.dev DNS zone. Required — no default. A missing value causes a plan-time error, preventing partial provisioning. (Requirement 6.6)"
  type        = string
  # No default — plan-time error if unset (Requirement 4.5, 6.6)
}

variable "cloudfront_domain_name" {
  description = "The CloudFront distribution domain name (*.cloudfront.net) — sourced from module.cdn.cloudfront_domain_name output. Used as the CNAME target for the root apex record."
  type        = string
}

variable "apex_domain" {
  description = "The root/apex domain name (e.g. 'vikram-sre.dev'). Used as the CNAME target for the www record."
  type        = string
}

variable "acm_validation_options" {
  description = "ACM domain validation options map from aws_acm_certificate.domain_validation_options — shape: map keyed by domain name, each value has name (CNAME record name), type (always CNAME), and value (CNAME record target). Sourced from module.cdn.acm_validation_options."
  type = map(object({
    name  = string
    type  = string
    value = string
  }))
}
