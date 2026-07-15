variable "bucket_name" {
  description = "Globally unique name for the Terraform state S3 bucket"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name for the DynamoDB state lock table"
  type        = string
}

variable "aws_region" {
  description = "AWS region where state backend resources are deployed (ap-south-1)"
  type        = string
}
