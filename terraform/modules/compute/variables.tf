# -----------------------------------------------------------------------------
# modules/compute — Input Variables
# Requirements: 8.1, 8.2, 9.1
# -----------------------------------------------------------------------------

variable "dynamodb_table_name" {
  description = "Physical name of the DynamoDB visitor-count table"
  type        = string
}

variable "lambda_handler" {
  description = "Lambda handler in <module>.<function> format (e.g., visitor_counter.lambda_handler)"
  type        = string
}

variable "lambda_source_dir" {
  description = "Path to the Lambda source directory used by archive_file to produce the deployment zip"
  type        = string
}

variable "lambda_execution_role_arn" {
  description = "IAM execution role ARN for the Lambda function — sourced from modules/iam output"
  type        = string
}

variable "cors_allow_origins" {
  description = "List of allowed CORS origins for the API Gateway HTTP API (e.g., [\"https://vikram-sre.dev\"])"
  type        = list(string)
}
