# -----------------------------------------------------------------------------
# Root outputs — Requirements: 14.3
# Outputs that propagate sensitive values are marked sensitive = true.
# -----------------------------------------------------------------------------

# State backend
output "state_bucket_arn" {
  description = "ARN of the Terraform remote state S3 bucket"
  value       = module.state_backend.state_bucket_arn
}

output "state_bucket_name" {
  description = "Name of the Terraform remote state S3 bucket"
  value       = module.state_backend.state_bucket_name
}

output "lock_table_name" {
  description = "Name of the DynamoDB state lock table"
  value       = module.state_backend.lock_table_name
}

# CDN
output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name (*.cloudfront.net)"
  value       = module.cdn.cloudfront_domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID — used for cache invalidations in CI/CD"
  value       = module.cdn.cloudfront_distribution_id
}

output "origin_bucket_arn" {
  description = "ARN of the private S3 origin bucket"
  value       = module.cdn.origin_bucket_arn
}

output "acm_certificate_arn" {
  description = "ARN of the validated ACM TLS certificate (us-east-1)"
  value       = module.cdn.acm_certificate_arn
}

# Compute
output "api_gateway_invoke_url" {
  description = "Full invoke URL for the API Gateway $default stage (visitor counter endpoint)"
  value       = module.compute.api_gateway_invoke_url
}

output "lambda_function_arn" {
  description = "ARN of the visitor counter Lambda function"
  value       = module.compute.lambda_function_arn
}

output "dynamodb_table_arn" {
  description = "ARN of the visitor-count DynamoDB table"
  value       = module.compute.dynamodb_table_arn
}

# IAM
output "deployment_role_arn" {
  description = "ARN of the GitHub Actions OIDC deployment role — set as AWS_DEPLOYMENT_ROLE_ARN secret"
  value       = module.iam.deployment_role_arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = module.iam.lambda_execution_role_arn
}

# DNS
output "apex_cname_id" {
  description = "Cloudflare record ID for the root apex CNAME"
  value       = module.dns.apex_cname_id
}

output "www_cname_id" {
  description = "Cloudflare record ID for the www CNAME"
  value       = module.dns.www_cname_id
}

# FinOps
output "budget_sns_topic_arn" {
  description = "ARN of the SNS topic receiving AWS Budget cost alert notifications"
  value       = aws_sns_topic.budget_alerts.arn
}
