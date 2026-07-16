# -----------------------------------------------------------------------------
# modules/compute — DynamoDB visitor-count table, Lambda function, API Gateway
#
# Provider: default aws (inherited from root — no required_providers block needed)
# Requirements: 7.1–7.6, 8.1–8.5, 9.1–9.4
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# DynamoDB — visitor-count table
# Requirements: 7.1, 7.2, 7.3, 7.4, 7.6
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "this" {
  name         = "visitor-count"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  server_side_encryption {
    enabled = true
    # No kms_master_key_id — AWS-owned KMS key per requirement 7.3
  }

  point_in_time_recovery {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Lambda — archive + function
# Requirements: 8.1, 8.2, 8.3, 8.4, 8.5
# -----------------------------------------------------------------------------
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "this" {
  # checkov:skip=CKV_AWS_116: Visitor counter is idempotent; DLQ adds cost without reliability benefit — ADR 0001
  # checkov:skip=CKV_AWS_50: X-Ray tracing omitted to stay within $6/mo FinOps hard cap
  function_name = "visitor-counter"
  runtime       = "python3.12"
  handler       = var.lambda_handler
  role          = var.lambda_execution_role_arn

  filename         = data.archive_file.lambda.output_path
  source_code_hash = filebase64sha256(data.archive_file.lambda.output_path)

  environment {
    variables = {
      # Value comes from var.dynamodb_table_name — never a string literal (req 8.3)
      DYNAMODB_TABLE_NAME = var.dynamodb_table_name
    }
  }
}

# -----------------------------------------------------------------------------
# API Gateway HTTP API — CORS, integration, route, stage, Lambda permission
# Requirements: 9.1, 9.2, 9.3, 9.4
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "this" {
  name          = "visitor-counter-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.cors_allow_origins
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "this" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.this.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 29000
}

resource "aws_apigatewayv2_route" "post_count" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "POST /count"
  target    = "integrations/${aws_apigatewayv2_integration.this.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
