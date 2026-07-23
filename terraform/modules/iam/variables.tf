variable "dynamodb_table_arn" {
  description = "ARN of the visitor-count DynamoDB table — scoped into the Lambda execution role inline policy"
  type        = string
}

variable "s3_origin_bucket_arn" {
  description = "ARN of the S3 origin bucket — scoped into the deployment role inline policy for frontend CI/CD"
  type        = string
}

variable "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution — scoped into the deployment role inline policy for cache invalidation"
  type        = string
}

variable "state_bucket_arn" {
  description = "ARN of the Terraform remote state S3 bucket — scoped into the deployment role inline policy for state r/w"
  type        = string
}

variable "state_lock_table_arn" {
  description = "ARN of the DynamoDB state-lock table — scoped into the deployment role inline policy for state locking"
  type        = string
}

variable "state_kms_key_arn" {
  description = "ARN of the KMS key used for Terraform state S3 bucket encryption — scoped into the deployment role for state decrypt/encrypt"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM TLS certificate (us-east-1) — scoped into the deployment role for terraform plan refresh"
  type        = string
}

variable "lambda_function_arn" {
  description = "ARN of the visitor-counter Lambda function — scoped into the deployment role for terraform plan refresh"
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the budget alerts SNS topic — scoped into the deployment role for terraform plan refresh"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID — used to construct budget ARN for IAM scoping"
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS region — used to construct API Gateway ARN for IAM scoping"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in org/repo format used to construct the OIDC sub claim (e.g. VikramBabariya/zero-trust-rac-platform)"
  type        = string
}

variable "github_branch" {
  description = "Branch name used to construct the OIDC sub claim (e.g. main)"
  type        = string
}
