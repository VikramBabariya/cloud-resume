output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution IAM role — consumed by modules/compute"
  value       = aws_iam_role.lambda_execution.arn
}

output "deployment_role_arn" {
  description = "ARN of the GitHub Actions OIDC deployment role — referenced in the terraform-cicd.yml workflow"
  value       = aws_iam_role.deployment.arn
}
