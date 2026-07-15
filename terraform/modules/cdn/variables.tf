variable "origin_bucket_name" {
  description = "Name for the S3 origin bucket — no default, plan fails if unset"
  type        = string
}

variable "domain_name" {
  description = "Primary domain name for the CloudFront distribution (e.g. vikram-sre.dev)"
  type        = string
}

variable "san_domain" {
  description = "Subject Alternative Name wildcard domain for the ACM certificate (e.g. *.vikram-sre.dev)"
  type        = string
}
