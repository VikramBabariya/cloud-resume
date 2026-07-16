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
# modules/iam — Lambda execution role, GitHub OIDC provider, deployment role
#
# Consumes outputs from modules/compute (dynamodb_table_arn) and modules/cdn
# (origin_bucket_arn, cloudfront_distribution_arn, state_bucket_arn). The
# apparent circularity with modules/compute is resolved at the root level —
# Terraform evaluates all module outputs before resolving inputs.
# Requirements: 10.1–10.5, 11.1–11.5
# -----------------------------------------------------------------------------
module "iam" {
  source = "./modules/iam"

  dynamodb_table_arn          = module.compute.dynamodb_table_arn
  s3_origin_bucket_arn        = module.cdn.origin_bucket_arn
  cloudfront_distribution_arn = module.cdn.cloudfront_distribution_arn
  state_bucket_arn            = module.state_backend.state_bucket_arn
  state_lock_table_arn        = "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/zero-trust-rac-tfstate-lock"
  github_repo                 = "VikramBabariya/zero-trust-rac-platform"
  github_branch               = "main"
}

# -----------------------------------------------------------------------------
# modules/compute — DynamoDB visitor-count table, Lambda function, API Gateway
#
# lambda_execution_role_arn resolved from module.iam output.
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
