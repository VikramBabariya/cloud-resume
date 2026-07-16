terraform {
  backend "s3" {
    bucket         = "zero-trust-rac-tfstate"
    key            = "prod/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "zero-trust-rac-tfstate-lock"
    kms_key_id     = "alias/terraform-state"
  }
}

module "state_backend" {
  source = "./modules/state-backend"

  bucket_name         = "zero-trust-rac-tfstate"
  dynamodb_table_name = "zero-trust-rac-tfstate-lock"
  aws_region          = var.aws_region
}

module "cdn" {
  source = "./modules/cdn"

  origin_bucket_name = "zero-trust-rac-origin"
  domain_name        = "vikram-sre.dev"
  san_domain         = "*.vikram-sre.dev"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

# -----------------------------------------------------------------------------
# modules/dns — Cloudflare CNAME records
#
# Consumes outputs from modules/cdn:
#   - cloudfront_domain_name   → root apex CNAME target
#   - acm_validation_options   → ACM validation CNAMEs (for_each)
#
# cloudflare_zone_id comes from the root sensitive variable — sourced at
# runtime via TF_VAR_cloudflare_zone_id (never hardcoded).
# Requirements: 6.4, 2.2
# -----------------------------------------------------------------------------
module "dns" {
  source = "./modules/dns"

  cloudflare_zone_id     = var.cloudflare_zone_id
  cloudfront_domain_name = module.cdn.cloudfront_domain_name
  acm_validation_options = module.cdn.acm_validation_options
  apex_domain            = "vikram-sre.dev"
}

# -----------------------------------------------------------------------------
# modules/compute — DynamoDB visitor-count table, Lambda function, API Gateway
#
# lambda_execution_role_arn references module.iam.lambda_execution_role_arn
# (modules/iam is wired in task 8; the forward reference resolves once modules/iam
# is created and the root is complete)
# Requirements: 2.2
# -----------------------------------------------------------------------------
module "compute" {
  source = "./modules/compute"

  dynamodb_table_name       = "visitor-count"
  lambda_handler            = "visitor_counter.lambda_handler"
  lambda_source_dir         = "${path.root}/../src/lambda"
  lambda_execution_role_arn = module.iam.lambda_execution_role_arn
  cors_allow_origins        = ["https://vikram-sre.dev"]
}
