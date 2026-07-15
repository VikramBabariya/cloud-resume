output "cloudfront_domain_name" {
  description = "The CloudFront distribution domain name (*.cloudfront.net) — consumed by modules/dns"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "cloudfront_distribution_id" {
  description = "The CloudFront distribution ID — consumed by CI/CD for cache invalidation"
  value       = aws_cloudfront_distribution.this.id
}

output "cloudfront_distribution_arn" {
  description = "The CloudFront distribution ARN — consumed by modules/iam deployment role policy"
  value       = aws_cloudfront_distribution.this.arn
}

output "origin_bucket_arn" {
  description = "The S3 origin bucket ARN — consumed by modules/iam deployment role policy"
  value       = aws_s3_bucket.origin.arn
}

output "acm_validation_options" {
  description = "ACM domain validation options map — consumed by modules/dns for CNAME record creation"
  value = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }
}

output "acm_certificate_arn" {
  description = "The validated ACM certificate ARN"
  value       = aws_acm_certificate_validation.this.certificate_arn
}
