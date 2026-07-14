# Requirements Document

## Introduction

This feature introduces Terraform-managed Infrastructure-as-Code (IaC) for the Zero-Trust RaC Platform, replacing the current manual ("ClickOps") backend provisioning with a fully declarative, version-controlled, and auditable infrastructure lifecycle. The scope covers all AWS resources backing the platform — S3 (static origin), CloudFront (CDN + TLS), ACM (certificate), API Gateway, Lambda (visitor counter), DynamoDB (visitor count store), IAM roles and policies (least-privilege execution and OIDC deployment), and the GitHub Actions OIDC Identity Provider — as well as the remote Terraform state backend (S3 + DynamoDB state locking). Cloudflare DNS records are also brought under Terraform management to eliminate manual DNS steps from the disaster recovery runbook. The infrastructure is organised into reusable, environment-aware modules, and all IaC changes are gated by a GitHub Actions CI/CD pipeline with shift-left static analysis (checkov).

---

## Glossary

- **Terraform_Root**: The root Terraform configuration that composes modules and manages the remote backend.
- **State_Backend**: The S3 bucket + DynamoDB table pair that stores and locks the Terraform state file.
- **Remote_State**: The `.tfstate` file stored in the State_Backend, representing the authoritative record of provisioned infrastructure.
- **Workspace**: A named Terraform workspace (e.g., `prod`) used to isolate state between environments.
- **Module**: A self-contained, reusable Terraform child module encapsulating a logical infrastructure concern.
- **OIDC_Provider**: The AWS IAM OpenID Connect Identity Provider that trusts GitHub Actions JWT tokens.
- **Deployment_Role**: The AWS IAM Role assumed by the GitHub Actions runner via OIDC for infrastructure deployments.
- **Lambda_Execution_Role**: The AWS IAM Role assumed by the visitor counter Lambda function at runtime.
- **OAC**: Origin Access Control — the CloudFront mechanism that restricts S3 bucket access exclusively to the designated CloudFront distribution.
- **Visitor_Counter_Lambda**: The Python 3.12 Lambda function that performs an atomic ADD on the DynamoDB visitor count item.
- **Visitor_Count_Table**: The DynamoDB On-Demand table storing the visitor count record.
- **ACM_Certificate**: The AWS Certificate Manager TLS certificate issued for `vikram-sre.dev` and `*.vikram-sre.dev`, provisioned in `us-east-1`.
- **CloudFront_Distribution**: The AWS CloudFront distribution serving static assets from the S3 origin with HTTPS enforcement.
- **API_Gateway**: The AWS API Gateway HTTP API acting as the secure entry point for the visitor counter backend.
- **S3_Origin_Bucket**: The private S3 bucket serving as the CloudFront origin for compiled static assets.
- **Terraform_Pipeline**: The GitHub Actions workflow responsible for running `terraform plan` and `terraform apply` on infrastructure changes.
- **IaC_Scanner**: The `checkov` static analysis security testing (SAST) tool (minimum version 3.2) that scans Terraform code for misconfigurations before apply.
- **tfvars_File**: A `.tfvars` file containing environment-specific variable values; secrets must never be stored in this file in plaintext.
- **Budget_Alarm**: The AWS Budgets alarm hard-capped at $6.00 USD / ₹500 INR per month.

---

## Requirements

### Requirement 1: Remote State Backend Bootstrapping

**User Story:** As a platform engineer, I want a secure, encrypted remote state backend, so that Terraform state is never stored locally, is protected from concurrent modification, and survives workstation loss.

#### Acceptance Criteria

1. THE Terraform_Root SHALL provision the State_Backend using an S3 bucket with server-side encryption using SSE-KMS and versioning enabled.
2. THE Terraform_Root SHALL provision a DynamoDB table for state locking with a partition key named `LockID` of type `String`, ensuring that concurrent `terraform apply` executions are serialised and cannot corrupt the Remote_State.
3. WHEN the State_Backend S3 bucket is created, THE Terraform_Root SHALL apply a bucket policy that denies `s3:PutObject` requests unless the `x-amz-server-side-encryption` header is present, enforcing encryption-at-rest on every state write.
4. THE State_Backend S3 bucket SHALL have public access blocked via all four S3 Block Public Access settings (`BlockPublicAcls`, `IgnorePublicAcls`, `BlockPublicPolicy`, `RestrictPublicBuckets`).
5. THE Terraform_Root SHALL configure the `backend "s3"` block with `encrypt = true`, referencing the State_Backend bucket, the DynamoDB locking table, and the `ap-south-1` region.

---

### Requirement 2: Module Structure and Repository Layout

**User Story:** As a platform engineer, I want infrastructure decomposed into focused, reusable Terraform modules, so that each AWS service layer can be tested, versioned, and modified in isolation without risking unintended side-effects to other layers.

#### Acceptance Criteria

1. THE Terraform_Root SHALL organise child Modules into exactly the following logical units: `modules/state-backend`, `modules/cdn`, `modules/compute`, `modules/dns`, and `modules/iam`; any addition of a new module SHALL be documented in an ADR before the module is created.
2. WHEN a Module is invoked, THE Terraform_Root SHALL pass only variables for which a corresponding `variable` block is declared inside the receiving module, with no undeclared variable passed to any module.
3. THE Terraform_Root SHALL declare all provider version constraints using `~>` pessimistic constraint operators for every provider block declared in the root configuration, preventing unintended major-version upgrades.
4. THE Terraform_Root SHALL declare a `required_terraform` version constraint of `>= 1.9.0` to ensure consistent CLI behaviour across all execution environments.
5. WHEN a new environment is added, THE Terraform_Root SHALL support it by creating a new Workspace and a corresponding `terraform.tfvars` file; no file under `modules/` SHALL be created, modified, or deleted during this operation.

---

### Requirement 3: S3 Origin Bucket Provisioning

**User Story:** As a platform engineer, I want the S3 origin bucket managed by Terraform, so that its private-only configuration, versioning, and OAC binding are declared as code and cannot be inadvertently misconfigured via the console.

#### Acceptance Criteria

1. THE `modules/cdn` Module SHALL provision the S3_Origin_Bucket with all four S3 Block Public Access settings enabled: `BlockPublicAcls`, `IgnorePublicAcls`, `BlockPublicPolicy`, and `RestrictPublicBuckets`.
2. THE `modules/cdn` Module SHALL attach a bucket policy to the S3_Origin_Bucket granting `s3:GetObject` exclusively to the `cloudfront.amazonaws.com` service principal conditioned on the `aws:SourceArn` matching the specific CloudFront_Distribution ARN — no other principal or distribution ARN SHALL satisfy the allow statement.
3. IF a direct `s3:GetObject` request arrives at the S3_Origin_Bucket without an `aws:SourceArn` matching the CloudFront_Distribution ARN, THEN THE S3_Origin_Bucket SHALL return an access denied error with no object data returned.
4. THE `modules/cdn` Module SHALL enable S3 versioning on the S3_Origin_Bucket with status set to `Enabled` (not `Suspended` or unset).
5. THE S3_Origin_Bucket name SHALL be an input variable with no default value, such that an unset variable causes `terraform plan` to exit with an error, ensuring no hardcoded bucket name exists in module source.

---

### Requirement 4: ACM Certificate Provisioning

**User Story:** As a platform engineer, I want the ACM TLS certificate managed by Terraform, so that certificate creation, DNS validation record injection, and CloudFront attachment are reproducible and documented as code.

#### Acceptance Criteria

1. THE `modules/cdn` Module SHALL provision the ACM_Certificate using an `aws` provider alias configured for the `us-east-1` region, as CloudFront requires certificates in that region regardless of the primary deployment region.
2. THE ACM_Certificate SHALL cover both `vikram-sre.dev` (domain name) and `*.vikram-sre.dev` as a Subject Alternative Name, with `aws_acm_certificate_validation` referencing the domain validation options for both names.
3. WHEN the ACM_Certificate is requested, THE `modules/dns` Module SHALL create one CNAME validation record in the Cloudflare DNS zone per SAN (two records total: one for the apex domain and one for the wildcard) using the `cloudflare` Terraform provider.
4. THE `modules/cdn` Module SHALL use `aws_acm_certificate_validation` with a `timeouts` block of `create = "45m"` to block the CloudFront_Distribution resource from being created until the ACM_Certificate status reaches `ISSUED`; if validation does not complete within 45 minutes, `terraform apply` SHALL time out with an error.
5. IF the Cloudflare DNS zone ID is not provided as an input variable, THEN THE `modules/dns` Module SHALL emit a plan-time error and halt, preventing partial provisioning; the variable SHALL have no default value.

---

### Requirement 5: CloudFront Distribution Provisioning

**User Story:** As a platform engineer, I want the CloudFront distribution declared in Terraform, so that its HTTPS-only enforcement, OAC binding, cache behaviours, and custom domain are version-controlled and reproducible.

#### Acceptance Criteria

1. THE `modules/cdn` Module SHALL provision the CloudFront_Distribution with `viewer_protocol_policy` set to `redirect-to-https` for the default cache behaviour and every ordered cache behaviour, ensuring no unencrypted traffic is served.
2. THE `modules/cdn` Module SHALL attach the ACM_Certificate (provisioned in `us-east-1`) to the CloudFront_Distribution and set `minimum_protocol_version` to `TLSv1.2_2021` or higher.
3. THE CloudFront_Distribution SHALL list `vikram-sre.dev` and `www.vikram-sre.dev` as aliases.
4. WHEN the CloudFront_Distribution is created, THE `modules/cdn` Module SHALL configure the S3_Origin_Bucket as the sole origin using OAC — no public S3 endpoint SHALL be exposed, and the S3 bucket policy SHALL deny all `s3:GetObject` requests whose `aws:SourceArn` does not match the CloudFront_Distribution ARN.
5. THE `modules/cdn` Module SHALL expose two named Terraform outputs: `cloudfront_domain_name` (the `*.cloudfront.net` domain) and `cloudfront_distribution_id`, making them available to `modules/dns` and the CI/CD pipeline without hard-coding.

---

### Requirement 6: Cloudflare DNS Record Management

**User Story:** As a platform engineer, I want Cloudflare DNS records managed by Terraform, so that the root CNAME flatten and `www` redirect records are reproducible and the DR runbook DNS recovery steps are fully automated.

#### Acceptance Criteria

1. THE `modules/dns` Module SHALL provision a Cloudflare DNS `CNAME` record for the root apex (`@`) pointing to the `cloudfront_domain_name` output with proxy status `false` (DNS-only, orange cloud disabled) and `ttl = 1` (Cloudflare automatic TTL).
2. THE `modules/dns` Module SHALL provision a Cloudflare DNS `CNAME` record for `www` pointing to `vikram-sre.dev` with proxy status `false` (DNS-only) and `ttl = 1`.
3. WHEN the CloudFront_Distribution domain name changes, THE `modules/dns` Module SHALL automatically update the root apex CNAME record on the next `terraform apply` without requiring manual Cloudflare console intervention.
4. THE Cloudflare API token used by the `cloudflare` provider SHALL be sourced exclusively from an environment variable or a Terraform variable marked `sensitive = true`; it SHALL NOT appear as a plaintext literal in any file committed to the repository.
5. THE `modules/dns` Module SHALL also provision the ACM DNS validation CNAME records with proxy status `false` and `ttl = 1`, ensuring that Cloudflare proxying does not interfere with ACM's HTTP polling and the full certificate issuance lifecycle is automated end-to-end.
6. THE Cloudflare Zone ID SHALL be supplied as an input variable with no default value, causing `terraform plan` to exit with an error if the variable is not supplied, ensuring portability across environments.

---

### Requirement 7: DynamoDB Visitor Count Table Provisioning

**User Story:** As a platform engineer, I want the DynamoDB table managed by Terraform, so that its schema, billing mode, and encryption settings are declared as code and consistent across any rebuild.

#### Acceptance Criteria

1. THE `modules/compute` Module SHALL provision the Visitor_Count_Table with the physical table name `visitor-count` and billing mode `PAY_PER_REQUEST` (On-Demand) to eliminate idle holding costs and stay within the FinOps budget cap.
2. THE Visitor_Count_Table SHALL define a partition key named `id` of type `String`.
3. THE `modules/compute` Module SHALL enable server-side encryption on the Visitor_Count_Table with `SSEEnabled = true` and no customer-managed key ARN, using the AWS-owned KMS key.
4. THE `modules/compute` Module SHALL enable Point-in-Time Recovery (PITR) on the Visitor_Count_Table.
5. THE `modules/compute` Module SHALL expose two named Terraform outputs: `dynamodb_table_arn` and `dynamodb_table_name`, consumed by the `modules/iam` Lambda_Execution_Role policy.
6. THE `modules/compute` Module SHALL declare a `lifecycle { prevent_destroy = true }` block on the Visitor_Count_Table resource to prevent accidental destruction and data loss during `terraform apply`.

---

### Requirement 8: Lambda Function Provisioning

**User Story:** As a platform engineer, I want the visitor counter Lambda function managed by Terraform, so that its runtime, handler, environment variables, and IAM execution role are version-controlled and reproducible.

#### Acceptance Criteria

1. THE `modules/compute` Module SHALL provision the Visitor_Counter_Lambda with runtime `python3.12` and the handler path declared as a Terraform input variable in the format `<module_filename>.<function_name>` with no path separators.
2. THE `modules/compute` Module SHALL package the Lambda deployment artifact using the `archive_file` data source with `type = "zip"` referencing the source directory path as an input variable, producing a deterministic archive (identical source content yields identical SHA-256 hash across independent runs).
3. THE `modules/compute` Module SHALL set the `DYNAMODB_TABLE_NAME` environment variable on the Visitor_Counter_Lambda to the `dynamodb_table_name` output from `modules/compute` — the value SHALL NOT be a string literal anywhere within the module source.
4. THE `modules/compute` Module SHALL set `source_code_hash = filebase64sha256(...)` on the Visitor_Counter_Lambda resource so that Terraform detects code changes and performs an in-place function update whenever the deployment package SHA-256 hash changes.
5. THE Visitor_Counter_Lambda SHALL be assigned the Lambda_Execution_Role ARN sourced from the `modules/iam` Module output.

---

### Requirement 9: API Gateway HTTP API Provisioning

**User Story:** As a platform engineer, I want the API Gateway HTTP API managed by Terraform, so that CORS policy, Lambda integration, routes, and the auto-deployed stage are reproducible and enforced as code.

#### Acceptance Criteria

1. THE `modules/compute` Module SHALL provision an API Gateway HTTP API (`aws_apigatewayv2_api`) with CORS configured to allow `allow_origins = ["https://vikram-sre.dev"]`, `allow_methods = ["POST", "OPTIONS"]`, `allow_headers = ["Content-Type"]`, and `max_age = 300`.
2. THE `modules/compute` Module SHALL provision an `AWS_PROXY` Lambda integration with a 29-second timeout, a `POST /count` route, and an auto-deployed `$default` stage.
3. THE `modules/compute` Module SHALL grant the API Gateway the `lambda:InvokeFunction` permission on the Visitor_Counter_Lambda via an `aws_lambda_permission` resource with `source_arn` scoped to `${aws_apigatewayv2_api.this.execution_arn}/*/*`.
4. IF a CORS preflight request arrives with an `Origin` header not matching `https://vikram-sre.dev`, THEN THE API_Gateway SHALL return a `403 Forbidden` response with no CORS headers present.
5. THE `modules/compute` Module SHALL expose a named Terraform output `api_gateway_invoke_url` containing the full `$default` stage invoke URL, available to the frontend build configuration.

---

### Requirement 10: IAM — Lambda Execution Role (Least Privilege)

**User Story:** As a platform engineer, I want the Lambda execution IAM role defined in Terraform with strict least-privilege policies, so that the visitor counter function cannot perform any AWS action beyond its explicitly required DynamoDB operations.

#### Acceptance Criteria

1. THE `modules/iam` Module SHALL provision the Lambda_Execution_Role with a trust policy containing exactly one principal — `lambda.amazonaws.com` — with no additional principals or condition blocks in the trust policy.
2. THE Lambda_Execution_Role inline policy SHALL grant exactly `dynamodb:UpdateItem` and `dynamodb:GetItem`, scoped strictly to the Visitor_Count_Table ARN — no wildcard resource ARNs are permitted.
3. THE Lambda_Execution_Role SHALL attach the AWS-managed `AWSLambdaBasicExecutionRole` policy to grant CloudWatch Logs write permissions required for Lambda function logging.
4. THE `modules/iam` Module SHALL declare the Visitor_Count_Table ARN as a required input variable with no default value, causing `terraform plan` to exit with an error if the variable is not supplied, ensuring the dependency is always explicitly resolved.
5. THE `modules/iam` Module SHALL expose a named Terraform output `lambda_execution_role_arn` for consumption by the `modules/compute` Module.

---

### Requirement 11: IAM — GitHub Actions OIDC Deployment Role

**User Story:** As a platform engineer, I want the GitHub Actions OIDC Identity Provider and deployment IAM role managed by Terraform, so that the Zero-Trust CI/CD authentication mechanism is itself version-controlled and its trust policy constraints are enforced declaratively.

#### Acceptance Criteria

1. THE `modules/iam` Module SHALL provision the OIDC_Provider for `token.actions.githubusercontent.com` with the thumbprint list containing both `6938fd4d98bab03faadb97b34396831e3780aea1` and `1c58a3a8518e8759bf075b76b750d4f2df264fcd`, enabling GitHub Actions JWT-based authentication and resilience to certificate rotation.
2. THE Deployment_Role trust policy SHALL restrict `sts:AssumeRoleWithWebIdentity` to tokens where the `sub` claim matches `repo:VikramBabariya/zero-trust-rac-platform:ref:refs/heads/main` exactly AND the `aud` claim equals `sts.amazonaws.com`, preventing cross-repository, cross-branch, and cross-audience token reuse.
3. THE Deployment_Role inline policy SHALL grant only the permissions strictly required for frontend CI/CD: `s3:ListBucket` scoped to the S3_Origin_Bucket ARN, `s3:PutObject` and `s3:DeleteObject` scoped to `${S3_Origin_Bucket_ARN}/*`, and `cloudfront:CreateInvalidation` scoped to the CloudFront_Distribution ARN.
4. WHERE a Terraform-managing workflow is added to GitHub Actions, THE Deployment_Role SHALL additionally include `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` on the State_Backend bucket, and `dynamodb:GetItem`, `dynamodb:PutItem`, `dynamodb:DeleteItem` on the state locking DynamoDB table.
5. THE `modules/iam` Module SHALL expose a named Terraform output `deployment_role_arn` so it can be referenced in the GitHub Actions workflow `role-to-assume` input without hardcoding.

---

### Requirement 12: Shift-Left IaC Security Scanning

**User Story:** As a platform engineer, I want static security analysis of all Terraform code executed in CI before any `terraform apply`, so that infrastructure misconfigurations are caught at pull-request time rather than after deployment.

#### Acceptance Criteria

1. THE Terraform_Pipeline SHALL run `terraform fmt -check` and `terraform validate` as the first two sequential steps; WHEN either step fails, THE pipeline SHALL exit immediately before proceeding to security scanning or plan.
2. THE Terraform_Pipeline SHALL execute the IaC_Scanner (`checkov` ≥ 3.2) as a required gate after format/validate and before any `terraform plan` or `terraform apply` step.
3. WHEN the IaC_Scanner detects a HIGH or CRITICAL severity misconfiguration, THE Terraform_Pipeline SHALL fail the job with a non-zero exit code and prevent the apply from executing.
4. WHEN the IaC_Scanner detects only MEDIUM or LOW severity findings, THE Terraform_Pipeline SHALL emit those findings as a non-blocking warning annotation and continue to the plan step without failing the job.
5. WHEN all quality gates and the IaC_Scanner pass on a pull request, THE Terraform_Pipeline SHALL overwrite (not append to) any previous plan comment on the same PR with the current `terraform plan` output; the workflow job SHALL have `permissions: pull-requests: write` declared to authorise this action.
6. THE Terraform_Pipeline SHALL authenticate to AWS using the OIDC_Provider and the Deployment_Role; no static `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` values SHALL appear in any workflow file or GitHub Secret for IaC operations.

---

### Requirement 13: FinOps Guardrails — Budget Alarm

**User Story:** As a platform engineer, I want the AWS Budgets alarm managed by Terraform, so that the ₹500 INR / $6 USD monthly hard cap and its notification thresholds are version-controlled and cannot be accidentally deleted via the console.

#### Acceptance Criteria

1. THE Terraform_Root SHALL provision an AWS Budget with a monthly limit of `6.00 USD`, `COST` type, and account-level scope covering all AWS services with no service-level filter applied.
2. WHEN actual costs reach 35% of the monthly limit ($2.10 USD), THE AWS Budget SHALL trigger a notification to an SNS topic provisioned by the Terraform_Root.
3. WHEN forecasted costs reach 100% of the monthly limit ($6.00 USD), THE AWS Budget SHALL trigger a notification to the same SNS topic.
4. THE notification email address SHALL be sourced from a Terraform variable marked `sensitive = true` and SHALL NOT be hardcoded as a string literal in any `.tf` file.
5. THE Terraform_Root SHALL provision the SNS topic and its email subscription before the AWS Budget resource is created; the SNS email subscription confirmation is a one-time manual step that SHALL be documented in the operations runbook as a prerequisite before cost alerts are active.

---

### Requirement 14: Secret and Sensitive Value Governance

**User Story:** As a platform engineer, I want all sensitive values (API tokens, account IDs, emails) handled exclusively via Terraform sensitive variables and environment variables, so that no secret is ever committed to the repository in plaintext.

#### Acceptance Criteria

1. THE Terraform_Root SHALL declare all sensitive inputs (Cloudflare API token, AWS account ID, notification email) using `variable` blocks with `sensitive = true`, causing Terraform to redact their values from plan and apply output.
2. THE Terraform_Root's `.gitignore` SHALL include `*.tfvars`, `*.tfstate`, and `*.tfstate.backup` patterns as standing controls, preventing accidental secret, state file, or state backup exposure regardless of when or whether a `.tfvars` file is present.
3. IF a sensitive variable is referenced in an `output` block in `outputs.tf`, THEN THE Terraform_Root SHALL mark that output block with `sensitive = true` to suppress its display in plan and apply output.
4. THE Terraform*Pipeline SHALL source sensitive variables exclusively from the GitHub Actions encrypted secrets named `CLOUDFLARE_API_TOKEN`, `AWS_ACCOUNT_ID`, and `NOTIFICATION_EMAIL`, injected as `TF_VAR*\*` environment variables at runtime; these values SHALL NOT appear in step logs, run summaries, or workflow artifacts.
5. THE Terraform_Root SHALL produce a documented `variables.tf` file listing every input variable with `description`, `type`, and `sensitive` attributes so that the full set of required secrets is self-documenting.
