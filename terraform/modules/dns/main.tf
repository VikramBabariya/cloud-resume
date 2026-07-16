# -----------------------------------------------------------------------------
# modules/dns — Cloudflare CNAME Records
#
# Provisions three categories of DNS records:
#   1. Root apex (@) CNAME → CloudFront distribution domain
#   2. www CNAME → apex domain (vikram-sre.dev)
#   3. ACM validation CNAMEs — one per SAN in the ACM certificate
#
# All records use:
#   proxied = false  (DNS-only; Cloudflare orange cloud disabled)
#   ttl     = 1      (Cloudflare automatic TTL)
#
# Requirements: 4.3, 6.1, 6.2, 6.3, 6.5
# Provider: cloudflare/cloudflare ~> 4.0
# -----------------------------------------------------------------------------

# Child modules that use a provider must declare it in required_providers so
# Terraform resolves the correct source address (cloudflare/cloudflare) rather
# than defaulting to the legacy hashicorp/ namespace which does not exist.
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

# -----------------------------------------------------------------------------
# 1. Root apex CNAME → CloudFront domain
#
# Cloudflare CNAME flattening resolves the apex CNAME transparently for DNS
# clients that do not support CNAME at the zone apex.
# proxied = false ensures ACM and CloudFront domain validation are not
# intercepted by Cloudflare's proxy layer.
# Requirements: 6.1, 6.3
# -----------------------------------------------------------------------------
resource "cloudflare_record" "apex" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "CNAME"
  value   = var.cloudfront_domain_name
  proxied = false
  ttl     = 1
}

# -----------------------------------------------------------------------------
# 2. www CNAME → apex domain
#
# Points www.vikram-sre.dev at the apex domain. CloudFront aliases include
# both vikram-sre.dev and www.vikram-sre.dev, so both resolve to CloudFront.
# Requirement: 6.2
# -----------------------------------------------------------------------------
resource "cloudflare_record" "www" {
  zone_id = var.cloudflare_zone_id
  name    = "www"
  type    = "CNAME"
  value   = var.apex_domain
  proxied = false
  ttl     = 1
}

# -----------------------------------------------------------------------------
# 3. ACM DNS validation CNAME records
#
# ACM emits one validation CNAME per SAN. The acm_validation_options map is
# keyed by domain name (e.g. "vikram-sre.dev", "*.vikram-sre.dev") and each
# value contains the CNAME name/type/value required for certificate issuance.
#
# Trailing dots are stripped from both name and value using trimsuffix() because
# ACM resource_record_name / resource_record_value include a trailing dot per
# RFC 1035, but Cloudflare's API does not expect or accept them.
#
# The apex domain suffix is also stripped from the name so Cloudflare receives
# only the relative label (e.g. "_abc123.vikram-sre.dev." → "_abc123"),
# since Cloudflare automatically appends the zone domain.
#
# proxied = false is critical — Cloudflare proxying would intercept the CNAME
# target, causing ACM's validation polling to fail certificate issuance.
# Requirements: 4.3, 6.5
# -----------------------------------------------------------------------------
resource "cloudflare_record" "acm_validation" {
  for_each = var.acm_validation_options

  zone_id = var.cloudflare_zone_id

  # Strip the trailing dot then strip the apex domain suffix so only the
  # relative label is submitted (Cloudflare appends the zone automatically).
  # e.g. "_abc123.vikram-sre.dev." → "_abc123"
  name = trimsuffix(
    trimsuffix(each.value.name, ".${var.apex_domain}."),
    "."
  )

  type = each.value.type

  # Strip trailing dot from the CNAME target value.
  # e.g. "_validationtoken.acm-validations.aws." → "_validationtoken.acm-validations.aws"
  value   = trimsuffix(each.value.value, ".")
  proxied = false
  ttl     = 1
}
