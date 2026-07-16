# -----------------------------------------------------------------------------
# modules/compute — Outputs
# Requirements: 7.5, 9.5
# -----------------------------------------------------------------------------

output "dynamodb_table_arn" {
  description = "ARN of the visitor-count DynamoDB table"
  value       = aws_dynamodb_table.this.arn
}

output "dynamodb_table_name" {
  description = "Name of the visitor-count DynamoDB table"
  value       = aws_dynamodb_table.this.name
}

output "api_gateway_invoke_url" {
  description = "Full invoke URL for the API Gateway $default stage"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "lambda_function_arn" {
  description = "ARN of the visitor counter Lambda function"
  value       = aws_lambda_function.this.arn
}
