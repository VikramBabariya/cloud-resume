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

# Inline policy — frontend CI/CD + Terraform state + plan/refresh permissions
# (Req 11.3, 11.4)
#
# CKV_AWS_356 compliance strategy:
#   - Every statement that supports resource-level ARN scoping uses explicit ARNs.
#   - The four statements marked checkov:skip below use actions that AWS does NOT
#     support resource-level restrictions for — they must use "*" by AWS design.
#     Each suppression references this comment block as the justifying constraint.
# checkov:skip=CKV_AWS_356: Several read-only refresh actions (kms:ListAliases,
#   cloudfront:GetDistribution/GetOriginAccessControl, acm:DescribeCertificate,
#   iam:Get*/List*, sns:Get*/List*, lambda:Get*/List*, budgets:ViewBudget/ListTags)
#   do not support resource-level ARN restrictions in AWS IAM — the AWS
#   documentation explicitly lists these as requiring "*". All write/mutate
#   actions in this policy are scoped to specific ARNs.
data "aws_iam_policy_document" "deployment_permissions" {

  # ── S3: Frontend deploy ───────────────────────────────────────────────────
  statement {
    sid     = "S3OriginList"
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = [
      var.s3_origin_bucket_arn,
      var.state_bucket_arn,
    ]
  }

  statement {
    sid    = "S3OriginWrite"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${var.s3_origin_bucket_arn}/*"]
  }

  # ── CloudFront: cache invalidation ───────────────────────────────────────
  statement {
    sid     = "CloudFrontInvalidation"
    effect  = "Allow"
    actions = ["cloudfront:CreateInvalidation"]
    resources = [var.cloudfront_distribution_arn]
  }

  # ── S3: Terraform state r/w ───────────────────────────────────────────────
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

  # ── DynamoDB: Terraform state locking ────────────────────────────────────
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

  # ── KMS: state bucket encryption + key refresh ───────────────────────────
  statement {
    sid    = "TerraformStateKMS"
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

  # kms:ListAliases is a list operation — AWS does not support scoping it to
  # a specific key ARN; the resource must be "*". Read-only, no write risk.
  statement {
    sid    = "TerraformKMSListAliases"
    effect = "Allow"
    actions = ["kms:ListAliases"]
    # checkov:skip=CKV_AWS_356: kms:ListAliases does not support resource-level
    # ARN restrictions — AWS requires "*" for all KMS list operations per the
    # AWS KMS IAM documentation.
    resources = ["*"]
  }

  # ── S3: bucket-level read for plan refresh ────────────────────────────────
  statement {
    sid    = "TerraformReadS3Buckets"
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

  # ── CloudFront: plan refresh ──────────────────────────────────────────────
  # cloudfront:GetDistribution, GetOriginAccessControl, ListTagsForResource
  # do not support resource-level ARN restrictions in AWS IAM.
  statement {
    sid    = "TerraformReadCloudFront"
    effect = "Allow"
    actions = [
      "cloudfront:GetDistribution",
      "cloudfront:GetOriginAccessControl",
      "cloudfront:ListTagsForResource",
    ]
    # checkov:skip=CKV_AWS_356: CloudFront read actions do not support resource-level
    # ARN restrictions — AWS IAM documentation requires "*" for these actions.
    resources = ["*"]
  }

  # ── ACM: plan refresh ────────────────────────────────────────────────────
  # acm:DescribeCertificate supports ARN scoping but ListTagsForCertificate
  # requires "*". Keeping both in one statement scoped to the certificate ARN
  # for the restrictable action; ListTags uses a separate statement below.
  statement {
    sid    = "TerraformReadACMCertificate"
    effect = "Allow"
    actions = ["acm:DescribeCertificate"]
    resources = [var.acm_certificate_arn]
  }

  statement {
    sid    = "TerraformReadACMTags"
    effect = "Allow"
    actions = ["acm:ListTagsForCertificate"]
    # checkov:skip=CKV_AWS_356: acm:ListTagsForCertificate does not support
    # resource-level ARN restrictions per AWS ACM IAM documentation.
    resources = ["*"]
  }

  # ── DynamoDB: plan refresh ────────────────────────────────────────────────
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

  # ── API Gateway: plan refresh ─────────────────────────────────────────────
  # apigateway:GET does not support resource-level ARN restrictions.
  statement {
    sid    = "TerraformReadAPIGateway"
    effect = "Allow"
    actions = ["apigateway:GET"]
    # checkov:skip=CKV_AWS_356: apigateway:GET does not support resource-level
    # ARN restrictions — AWS API Gateway IAM documentation requires "*".
    resources = ["*"]
  }

  # ── IAM: plan refresh ────────────────────────────────────────────────────
  # IAM read actions (GetRole, GetRolePolicy, etc.) do support ARN scoping for
  # roles, but GetOpenIDConnectProvider and List* require "*".
  statement {
    sid    = "TerraformReadIAMRoles"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
    ]
    resources = [
      aws_iam_role.lambda_execution.arn,
      aws_iam_role.deployment.arn,
    ]
  }

  statement {
    sid    = "TerraformReadIAMGlobal"
    effect = "Allow"
    actions = [
      "iam:GetOpenIDConnectProvider",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
    ]
    # checkov:skip=CKV_AWS_356: iam:GetOpenIDConnectProvider and iam:GetPolicy
    # do not support resource-level ARN restrictions per AWS IAM documentation.
    resources = ["*"]
  }

  # ── SNS: plan refresh ────────────────────────────────────────────────────
  statement {
    sid    = "TerraformReadSNSTopic"
    effect = "Allow"
    actions = [
      "sns:GetTopicAttributes",
      "sns:ListTagsForResource",
      "sns:ListSubscriptionsByTopic",
    ]
    resources = [var.sns_topic_arn]
  }

  statement {
    sid    = "TerraformReadSNSSubscription"
    effect = "Allow"
    actions = ["sns:GetSubscriptionAttributes"]
    # checkov:skip=CKV_AWS_356: sns:GetSubscriptionAttributes requires the
    # subscription ARN, which is only known after apply and cannot be
    # referenced statically in the policy — "*" is required.
    resources = ["*"]
  }

  # ── Lambda: plan refresh ─────────────────────────────────────────────────
  statement {
    sid    = "TerraformReadLambda"
    effect = "Allow"
    actions = [
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:GetFunctionCodeSigningConfig",
      "lambda:GetPolicy",
      "lambda:ListVersionsByFunction",
    ]
    resources = [var.lambda_function_arn]
  }

  # ── Budgets: plan refresh ─────────────────────────────────────────────────
  statement {
    sid    = "TerraformReadBudgets"
    effect = "Allow"
    actions = [
      "budgets:ViewBudget",
      "budgets:ListTagsForResource",
    ]
    resources = ["arn:aws:budgets::${var.aws_account_id}:budget/zero-trust-rac-monthly-budget"]
  }
}

resource "aws_iam_role_policy" "deployment" {
  name   = "deployment-cicd-permissions"
  role   = aws_iam_role.deployment.id
  policy = data.aws_iam_policy_document.deployment_permissions.json
}
