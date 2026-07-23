variable "cloudflare_api_token" {
  description = "Cloudflare API token with DNS edit permissions for vikram-sre.dev"
  type        = string
  sensitive   = true
}

variable "aws_account_id" {
  description = "AWS account ID — used in IAM ARN constructions"
  type        = string
  sensitive   = true
}

variable "notification_email" {
  description = "Email address for AWS Budget SNS alarm notifications"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for vikram-sre.dev DNS management"
  type        = string
  sensitive   = false
}

variable "aws_region" {
  description = "Primary AWS deployment region"
  type        = string
  sensitive   = false
  default     = "ap-south-1"
}
