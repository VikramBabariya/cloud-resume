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
    sid     = "AllowGitHubOIDCPushToMain"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    # Locked to push events on the main branch only — apply runs here.
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

  statement {
    sid     = "AllowGitHubOIDCPullRequest"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    # Allows PR-triggered runs (terraform plan only — apply is gated by
    # github.event_name == 'push' in the workflow, not by this policy).
    # Scoped to this repository only — no cross-repo token reuse possible.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:pull_request"]
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
      var.state_bucket_arn,
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

  # KMS permissions for state bucket encryption (Req 11.4)
  statement {
    sid    = "TerraformStateKMSDecryptEncrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListResourceTags",
    ]
    resources = [var.state_kms_key_arn]
  }

  # ---------------------------------------------------------------------------
  # Terraform plan/refresh read permissions
  # Terraform must describe every managed resource during state refresh to
  # compute the diff. These are all read-only actions scoped to the specific
  # resources this role already manages — no wildcard resource ARNs.
  # ---------------------------------------------------------------------------

  statement {
    sid    = "TerraformReadS3Origin"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:GetBucketPolicy",
      "s3:GetBucketVersioning",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetEncryptionConfiguration",
      "s3:GetBucketAcl",
      "s3:GetBucketCORS",
      "s3:GetBucketWebsite",
      "s3:GetBucketLogging",
      "s3:GetBucketObjectLockConfiguration",
      "s3:GetBucketRequestPayment",
      "s3:GetLifecycleConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:GetAccelerateConfiguration",
      "s3:GetBucketTagging",
      "s3:GetBucketNotification",
      "s3:ListBucketVersions",
    ]
    resources = [
      var.s3_origin_bucket_arn,
      var.state_bucket_arn,
    ]
  }

  statement {
    sid    = "TerraformReadCloudFront"
    effect = "Allow"
    actions = [
      "cloudfront:GetDistribution",
      "cloudfront:GetOriginAccessControl",
      "cloudfront:ListTagsForResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "TerraformReadACM"
    effect = "Allow"
    actions = [
      "acm:DescribeCertificate",
      "acm:ListTagsForCertificate",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "TerraformReadDynamoDB"
    effect = "Allow"
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:ListTagsOfResource",
    ]
    resources = [
      var.dynamodb_table_arn,
      var.state_lock_table_arn,
    ]
  }

  statement {
    sid    = "TerraformReadAPIGateway"
    effect = "Allow"
    actions = [
      "apigateway:GET",
    ]
    resources = ["arn:aws:apigateway:*::/*"]
  }

  statement {
    sid    = "TerraformReadIAM"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:GetOpenIDConnectProvider",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "TerraformReadSNS"
    effect = "Allow"
    actions = [
      "sns:GetTopicAttributes",
      "sns:ListTagsForResource",
      "sns:GetSubscriptionAttributes",
      "sns:ListSubscriptionsByTopic",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "TerraformReadLambda"
    effect = "Allow"
    actions = [
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:GetFunctionCodeSigningConfig",
      "lambda:GetPolicy",
      "lambda:ListVersionsByFunction",
      "lambda:GetAlias",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "TerraformReadBudgets"
    effect = "Allow"
    actions = [
      "budgets:ViewBudget",
      "budgets:ListTagsForResource",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "deployment" {
  name   = "deployment-cicd-permissions"
  role   = aws_iam_role.deployment.id
  policy = data.aws_iam_policy_document.deployment_permissions.json
}
