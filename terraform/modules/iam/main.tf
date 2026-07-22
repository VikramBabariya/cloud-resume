# ---------------------------------------------------------------------------
# Lambda Execution Role
# Trust policy: lambda.amazonaws.com only — exactly one principal, no wildcards,
# no conditions (Requirement 10.1)
# ---------------------------------------------------------------------------

# adding a comment to trigger actions workflow

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    sid     = "AllowLambdaAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_execution" {
  name               = "zero-trust-rac-lambda-execution-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json

  tags = {
    Purpose = "visitor-counter-lambda-execution"
  }
}

# Inline policy: exactly dynamodb:UpdateItem and dynamodb:GetItem scoped to the
# visitor-count table ARN — no wildcard resource ARN (Requirement 10.2)
data "aws_iam_policy_document" "lambda_dynamodb" {
  statement {
    sid    = "DynamoDBVisitorCountAccess"
    effect = "Allow"
    actions = [
      "dynamodb:UpdateItem",
      "dynamodb:GetItem",
    ]
    resources = [var.dynamodb_table_arn]
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb" {
  name   = "lambda-dynamodb-visitor-count"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_dynamodb.json
}

# AWS-managed policy attachment for CloudWatch Logs write access (Requirement 10.3)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC Identity Provider
# Both thumbprints included for certificate rotation resilience (Req 11.1)
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # Two thumbprints — current + rotation candidate — so certificate rotation
  # by GitHub does not break CI/CD authentication.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = {
    Purpose = "github-actions-oidc"
  }
}

# ---------------------------------------------------------------------------
# GitHub Actions Deployment Role
# Trust policy: sts:AssumeRoleWithWebIdentity, StringEquals on BOTH sub AND aud
# — prevents cross-repository, cross-branch, and cross-audience token reuse (Req 11.2)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "deployment_trust" {
  statement {
    sid     = "AllowGitHubOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "deployment" {
  name               = "zero-trust-rac-deployment-role"
  assume_role_policy = data.aws_iam_policy_document.deployment_trust.json

  tags = {
    Purpose = "github-actions-cicd-deployment"
  }
}

# Inline policy — frontend CI/CD + Terraform state permissions (Req 11.3, 11.4)
data "aws_iam_policy_document" "deployment_permissions" {
  # Frontend CI/CD: sync dist/ to S3 origin bucket (Req 11.3)
  statement {
    sid     = "S3OriginListBucket"
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = [
      var.s3_origin_bucket_arn,
    ]
  }

  statement {
    sid    = "S3OriginReadWrite"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${var.s3_origin_bucket_arn}/*"]
  }

  statement {
    sid     = "CloudFrontInvalidation"
    effect  = "Allow"
    actions = ["cloudfront:CreateInvalidation"]
    resources = [
      var.cloudfront_distribution_arn,
    ]
  }

  # Terraform state backend r/w (Req 11.4)
  statement {
    sid    = "TerraformStateReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      var.state_bucket_arn,
      "${var.state_bucket_arn}/*",
    ]
  }

  statement {
    sid    = "TerraformStateLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
    ]
    resources = [var.state_lock_table_arn]
  }
}

resource "aws_iam_role_policy" "deployment" {
  name   = "deployment-cicd-permissions"
  role   = aws_iam_role.deployment.id
  policy = data.aws_iam_policy_document.deployment_permissions.json
}
