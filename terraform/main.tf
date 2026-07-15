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

