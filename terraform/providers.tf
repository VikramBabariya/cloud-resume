provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "zero-trust-rac-platform"
      Environment = "prod"
      ManagedBy   = "terraform"
      Owner       = "VikramBabariya"
      Repository  = "github.com/VikramBabariya/zero-trust-rac-platform"
    }
  }
}

# Provider alias required for CloudFront ACM certificates (must be in us-east-1)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "zero-trust-rac-platform"
      Environment = "prod"
      ManagedBy   = "terraform"
      Owner       = "VikramBabariya"
      Repository  = "github.com/VikramBabariya/zero-trust-rac-platform"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
