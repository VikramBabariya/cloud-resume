# Implementation Plan: Terraform Infrastructure Management

## Overview

Convert all ClickOps-provisioned AWS resources for the Zero-Trust RaC Platform into a fully declarative, version-controlled Terraform codebase. Implementation is organised as a root configuration composing five child modules (`state-backend`, `cdn`, `compute`, `dns`, `iam`), gated by a GitHub Actions CI/CD pipeline with shift-left static analysis via checkov. Tasks proceed from repository scaffolding → module-by-module resource implementation → root wiring → pipeline authoring → post-apply smoke tests → runbook update.

This is pure Infrastructure-as-Code. There are no pure functions with randomised input/output behaviour, so property-based tests are not applicable. All testing is layered static analysis, plan validation, and post-apply AWS CLI smoke tests.

---

## Tasks

- [x] 0. Documentation-first: update all docs and README to reflect IaC integration before writing any Terraform code
  - [x] 0.1 Create `docs/adr/0009-terraform-iac-adoption.md` — ADR documenting the decision to replace ClickOps with Terraform
    - Record the **context**: all backend resources (S3, CloudFront, ACM, API Gateway, Lambda, DynamoDB, IAM, OIDC provider) are currently provisioned manually; Cloudflare DNS records require manual intervention during DR; no auditable change history for infrastructure mutations
    - Record the **decision**: adopt Terraform >= 1.9.0 with a remote S3+DynamoDB state backend as the single IaC tool for all AWS and Cloudflare resources; organise into five child modules (`state-backend`, `cdn`, `compute`, `dns`, `iam`)
    - Record the **consequences**: ClickOps steps in `docs/RUNBOOK.md` Section 5 are deprecated and replaced by `terraform apply`; a one-time bootstrap sequence is required; the `terraform/` directory becomes a first-class project artifact alongside `src/` and `data/`
    - Record **alternatives considered**: AWS CDK (rejected — Python runtime dependency adds toolchain complexity), Pulumi (rejected — smaller community and no checkov native support), manual CloudFormation (rejected — verbose, no Cloudflare provider)
    - _Requirements: 2.1_
  - [x] 0.2 Update `README.md` — replace the "Epic 5: Future IaC Evolution" section with an "Infrastructure as Code" section reflecting current state
    - Replace the future-tense "Epic 5" section with a present-tense **Infrastructure as Code** section describing:
      - The `terraform/` directory structure and its five modules
      - The two CI/CD pipelines: `front-end-cicd.yml` (frontend, unchanged) and `terraform-cicd.yml` (new IaC pipeline)
      - The shift-left gate sequence: `fmt → validate → checkov → plan → apply`
    - Update the **DevSecOps Toolchain** table: add a new row for `Infrastructure as Code` with value `Terraform >= 1.9.0 (hashicorp/aws ~> 5.0, cloudflare/cloudflare ~> 4.0), checkov >= 3.2`; change the `CI/CD & Quality Gates` row to include `checkov (IaC SAST)`
    - Add `ADR 0009` to the Architecture Decision Records list
    - Update the **Operational Workflows** — add a **Flow C: IaC Deployment** paragraph: Terraform pipeline authenticates via OIDC, runs checkov security scan, posts plan output as a PR comment, and applies on merge to `main`
    - _Requirements: 2.1, 12.1, 12.2_
  - [x] 0.3 Update `docs/RUNBOOK.md` — deprecate the ClickOps Section 5 and add the IaC bootstrap section
    - In **Section 5 ("Backend Resource Provisioning")**: prepend a deprecation notice block stating this section is superseded by Terraform; keep the original steps as a historical reference but mark them as deprecated
    - Add a new **Section 6: IaC Bootstrap Prerequisites** (renumber existing Section 6 DR to Section 7) covering the one-time manual bootstrap sequence:
      - Step 1: Create KMS key `alias/terraform-state` in `ap-south-1` via AWS console (one-time only — cannot be managed by Terraform before state backend exists)
      - Step 2: Create S3 bucket `zero-trust-rac-tfstate` with SSE-KMS and versioning enabled
      - Step 3: Create DynamoDB table `zero-trust-rac-tfstate-lock` with partition key `LockID` (String)
      - Step 4: Run `terraform init` inside `terraform/` — the `backend "s3"` block will connect to the bootstrapped bucket
      - Step 5: Run `terraform apply` — after apply completes, confirm the SNS email subscription to activate cost alerts (one-time manual step)
      - State lock recovery: `terraform force-unlock <LOCK_ID>` — use only when a failed apply leaves an orphaned lock; always check CloudTrail before force-unlocking
    - Add a new **Section 8: IaC Day-2 Operations** covering: running `terraform plan` locally, how to add a new environment (new workspace + `terraform.tfvars`), and how to read checkov suppression comments
    - _Requirements: 1.5, 13.5_
  - [x] 0.4 Update `docs/SECURITY.md` — add IaC security posture to the existing security pillars
    - In **Section 2 (Identity Governance)**: extend the existing OIDC paragraph to note that the deployment role trust policy is now declared in Terraform (`modules/iam`) with `sub` claim locked to `repo:VikramBabariya/zero-trust-rac-platform:ref:refs/heads/main` and `aud = "sts.amazonaws.com"`, making the trust policy constraint version-controlled and auditable
    - Add a new **Section 5: Infrastructure-as-Code Security Controls** covering:
      - Remote state encryption: Terraform state stored in S3 with SSE-KMS; `s3:PutObject` denied without `x-amz-server-side-encryption: aws:kms` header
      - State access control: state bucket and DynamoDB lock table access is scoped exclusively to the deployment role; no public access
      - Shift-left IaC scanning: checkov >= 3.2 runs as a required gate before every `terraform plan`; HIGH/CRITICAL findings block apply; intentional waivers are inline `# checkov:skip` comments referencing the relevant ADR
      - Sensitive variable governance: all secrets flow via `GitHub Secret → TF_VAR_* env var → sensitive = true Terraform variable → redacted in plan/apply output`; no plaintext secrets in any `.tf` or `.tfvars` file committed to the repository
    - _Requirements: 12.2, 12.3, 14.1, 14.4_
  - [x] 0.5 Update `docs/architecture/source/system-design.md` — add the Terraform pipeline to the system topology diagram
    - Add a new `subgraph` for the Terraform IaC pipeline inside the existing `Tier_OIDC` subgraph or as a sibling subgraph titled `"Terraform IaC Pipeline"`:
      - Node: `TF_Pipeline["terraform-cicd.yml\nfmt → validate → checkov → plan → apply"]` (cicd class)
      - Node: `TF_State["S3 State Backend\n(SSE-KMS, versioning)"]` (db class)
      - Node: `TF_Lock["DynamoDB Lock\n(LockID)"]` (db class)
    - Add edges: `TF_Pipeline -->|"OIDC AssumeRoleWithWebIdentity"| IAM`, `TF_Pipeline -->|"terraform state r/w"| TF_State`, `TF_Pipeline -->|"state lock/unlock"| TF_Lock`, `TF_Pipeline -->|"provisions all AWS resources"| CF`, `TF_Pipeline -->|"provisions all AWS resources"| S3`
    - Add a legend note that `GHRunner` (frontend pipeline) and `TF_Pipeline` (IaC pipeline) are separate workflow files sharing the same OIDC trust with different `role-session-name` values
    - _Requirements: 2.1_

- [x] 1. Scaffold Terraform repository layout and root configuration files
  - Create `terraform/` directory with the following files: `versions.tf`, `providers.tf`, `variables.tf`, `outputs.tf`, `main.tf`, `terraform.tfvars.example`
  - Create skeleton module directories: `terraform/modules/state-backend/`, `modules/cdn/`, `modules/compute/`, `modules/dns/`, `modules/iam/` — each with empty `main.tf`, `variables.tf`, `outputs.tf`
  - In `versions.tf`: declare `required_version = ">= 1.9.0"` and `required_providers` for `hashicorp/aws ~> 5.0`, `cloudflare/cloudflare ~> 4.0`, `hashicorp/archive ~> 2.0` using `~>` pessimistic constraint operators
  - In `providers.tf`: configure default `aws` provider (`region = var.aws_region`), `aws` alias `us_east_1` (`region = "us-east-1"`) for ACM, and `cloudflare` provider (`api_token = var.cloudflare_api_token`)
  - In `variables.tf`: declare `cloudflare_api_token` (`sensitive = true`), `aws_account_id` (`sensitive = true`), `notification_email` (`sensitive = true`), `cloudflare_zone_id`, `aws_region` — each with `description`, `type`, and `sensitive` attributes
  - Create `terraform/.gitignore` covering `*.tfvars`, `*.tfstate`, `*.tfstate.backup`, `.terraform/` — note: `.terraform.lock.hcl` should be committed and must NOT be in this gitignore
  - Populate `terraform.tfvars.example` documenting every required variable with a description and example value (no real secrets)
  - Stub `main.tf` and `outputs.tf` as empty root files ready for module blocks
  - _Requirements: 2.1, 2.3, 2.4, 14.1, 14.2, 14.5_

- [x] 2. Implement `modules/state-backend` — S3 state bucket and DynamoDB lock table
  - [x] 2.1 Write `modules/state-backend/variables.tf` declaring `bucket_name`, `dynamodb_table_name`, `kms_key_arn`, and `aws_region` — all required with no defaults
    - _Requirements: 1.1, 1.2_
  - [x] 2.2 Write `modules/state-backend/main.tf`:
    - `aws_s3_bucket` with `aws_s3_bucket_server_side_encryption_configuration` using SSE-KMS (`kms_master_key_id = var.kms_key_arn`, `sse_algorithm = "aws:kms"`)
    - `aws_s3_bucket_versioning` with `status = "Enabled"`
    - `aws_s3_bucket_public_access_block` with all four flags set to `true` (`block_public_acls`, `ignore_public_acls`, `block_public_policy`, `restrict_public_buckets`)
    - `aws_s3_bucket_policy` with a `Deny` statement on `s3:PutObject` when `StringNotEquals: s3:x-amz-server-side-encryption: "aws:kms"` (see design for exact policy JSON)
    - `aws_dynamodb_table` with `hash_key = "LockID"` (type `String`), `billing_mode = "PAY_PER_REQUEST"`
    - _Requirements: 1.1, 1.2, 1.3, 1.4_
  - [x] 2.3 Write `modules/state-backend/outputs.tf` exposing `state_bucket_arn`, `state_bucket_name`, `lock_table_name`
    - _Requirements: 1.2_
  - [x] 2.4 Wire `modules/state-backend` into `terraform/main.tf` and add the `backend "s3"` block with `bucket = "zero-trust-rac-tfstate"`, `key = "prod/terraform.tfstate"`, `region = "ap-south-1"`, `encrypt = true`, `dynamodb_table = "zero-trust-rac-tfstate-lock"`, `kms_key_id = "alias/terraform-state"`
    - _Requirements: 1.5_

- [ ] 3. Implement `modules/cdn` — S3 origin bucket, OAC, ACM certificate, CloudFront distribution
  - [ ] 3.1 Write `modules/cdn/variables.tf` declaring `origin_bucket_name` (required, no default — missing causes plan-time error), `domain_name`, `san_domain`, and a `providers` pass-through map for the `us_east_1` alias
    - _Requirements: 3.5_
  - [ ] 3.2 Implement S3 origin bucket resources in `modules/cdn/main.tf`:
    - `aws_s3_bucket` (private)
    - `aws_s3_bucket_public_access_block` with all four flags set to `true`
    - `aws_s3_bucket_versioning` with `status = "Enabled"`
    - `aws_cloudfront_origin_access_control` resource bound to the S3 origin
    - `aws_s3_bucket_policy` granting `s3:GetObject` to `cloudfront.amazonaws.com` conditioned on `AWS:SourceArn` matching the CloudFront distribution ARN (see design for exact OAC-only policy JSON)
    - _Requirements: 3.1, 3.2, 3.3, 3.4_
  - [ ] 3.3 Implement ACM certificate in `modules/cdn/main.tf` using the `aws.us_east_1` provider alias:
    - `aws_acm_certificate` with `domain_name = var.domain_name`, `subject_alternative_names = [var.san_domain]`, `validation_method = "DNS"`
    - `aws_acm_certificate_validation` with `timeouts { create = "45m" }` consuming CNAME records from `modules/dns`
    - _Requirements: 4.1, 4.2, 4.4_
  - [ ] 3.4 Implement CloudFront distribution in `modules/cdn/main.tf`:
    - `aws_cloudfront_distribution` with `viewer_protocol_policy = "redirect-to-https"`, `minimum_protocol_version = "TLSv1.2_2021"`, OAC-bound S3 origin, `aliases = ["vikram-sre.dev", "www.vikram-sre.dev"]`, and the validated ACM certificate
    - Ensure `default_cache_behavior` (and any ordered cache behaviour) also has `viewer_protocol_policy = "redirect-to-https"`
    - _Requirements: 5.1, 5.2, 5.3, 5.4_
  - [ ] 3.5 Write `modules/cdn/outputs.tf` exposing `cloudfront_domain_name`, `cloudfront_distribution_id`, `cloudfront_distribution_arn`, `origin_bucket_arn`, `acm_validation_options`, `acm_certificate_arn`
    - _Requirements: 5.5_
  - [ ] 3.6 Wire `modules/cdn` into `terraform/main.tf` passing all required variables and the `providers = { aws.us_east_1 = aws.us_east_1 }` alias map
    - _Requirements: 2.2_

- [ ] 4. Implement `modules/dns` — Cloudflare CNAME records
  - [ ] 4.1 Write `modules/dns/variables.tf` declaring `cloudflare_zone_id` (required, no default — missing causes plan-time error), `cloudfront_domain_name`, `apex_domain`, `acm_validation_options`
    - _Requirements: 4.5, 6.6_
  - [ ] 4.2 Implement DNS records in `modules/dns/main.tf`:
    - `cloudflare_record` for root apex (`@`) CNAME → `var.cloudfront_domain_name`, `proxied = false`, `ttl = 1`
    - `cloudflare_record` for `www` CNAME → `vikram-sre.dev`, `proxied = false`, `ttl = 1`
    - `cloudflare_record` resources for ACM validation CNAMEs using `for_each` over `var.acm_validation_options`, each with `proxied = false`, `ttl = 1`
    - _Requirements: 4.3, 6.1, 6.2, 6.3, 6.5_
  - [ ] 4.3 Write `modules/dns/outputs.tf` exposing `apex_cname_id` and `www_cname_id`
  - [ ] 4.4 Wire `modules/dns` into `terraform/main.tf` passing `cloudflare_zone_id = var.cloudflare_zone_id`, `cloudfront_domain_name = module.cdn.cloudfront_domain_name`, `acm_validation_options = module.cdn.acm_validation_options`
    - _Requirements: 6.4, 2.2_

- [ ] 5. Checkpoint — validate module wiring up to dns/cdn/state-backend
  - Run `terraform fmt -recursive` inside `terraform/` and confirm zero formatting errors
  - Run `terraform validate` (after `terraform init`) and confirm no schema, type, or reference errors
  - Confirm all module input/output bindings compile cleanly with no unresolved references
  - Ask the user if any questions arise before continuing.

- [ ] 6. Implement `modules/compute` — DynamoDB visitor-count table, Lambda function, and API Gateway
  - [ ] 6.1 Write `modules/compute/variables.tf` declaring `dynamodb_table_name`, `lambda_handler`, `lambda_source_dir`, `lambda_execution_role_arn`, `cors_allow_origins` (type `list(string)`)
    - _Requirements: 8.1, 8.2, 9.1_
  - [ ] 6.2 Implement DynamoDB visitor-count table in `modules/compute/main.tf`:
    - `aws_dynamodb_table` with `name = "visitor-count"`, `billing_mode = "PAY_PER_REQUEST"`, `hash_key = "id"` (type `String`)
    - `server_side_encryption` block with `enabled = true` (AWS-owned KMS key, no customer-managed key ARN)
    - `point_in_time_recovery` block with `enabled = true`
    - `lifecycle { prevent_destroy = true }` to guard against accidental data loss
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.6_
  - [ ] 6.3 Implement Lambda function in `modules/compute/main.tf`:
    - `data "archive_file"` with `type = "zip"`, `source_dir = var.lambda_source_dir`
    - `aws_lambda_function` with `runtime = "python3.12"`, `handler = var.lambda_handler`, `source_code_hash = filebase64sha256(data.archive_file.lambda.output_path)`, `role = var.lambda_execution_role_arn`
    - `environment { variables = { DYNAMODB_TABLE_NAME = var.dynamodb_table_name } }` — never a string literal
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_
  - [ ] 6.4 Implement API Gateway HTTP API in `modules/compute/main.tf`:
    - `aws_apigatewayv2_api` with `protocol_type = "HTTP"` and `cors_configuration` block: `allow_origins = var.cors_allow_origins` (e.g. `["https://vikram-sre.dev"]`), `allow_methods = ["POST", "OPTIONS"]`, `allow_headers = ["Content-Type"]`, `max_age = 300`
    - `aws_apigatewayv2_integration` of type `AWS_PROXY` with `timeout_milliseconds = 29000`
    - `aws_apigatewayv2_route` for `POST /count`
    - `aws_apigatewayv2_stage` with `name = "$default"`, `auto_deploy = true`
    - `aws_lambda_permission` granting `lambda:InvokeFunction` with `source_arn = "${aws_apigatewayv2_api.this.execution_arn}/*/*"`
    - _Requirements: 9.1, 9.2, 9.3, 9.4_
  - [ ] 6.5 Write `modules/compute/outputs.tf` exposing `dynamodb_table_arn`, `dynamodb_table_name`, `api_gateway_invoke_url`, `lambda_function_arn`
    - _Requirements: 7.5, 9.5_
  - [ ] 6.6 Wire `modules/compute` into `terraform/main.tf`; stub `lambda_execution_role_arn` with `module.iam.lambda_execution_role_arn` (resolved in task 8)
    - _Requirements: 2.2_

- [ ] 7. Implement `modules/iam` — Lambda execution role, GitHub OIDC provider, and deployment role
  - [ ] 7.1 Write `modules/iam/variables.tf` declaring all required inputs with no defaults: `dynamodb_table_arn`, `s3_origin_bucket_arn`, `cloudfront_distribution_arn`, `state_bucket_arn`, `state_lock_table_arn`, `github_repo`, `github_branch`
    - The `dynamodb_table_arn` variable must be declared with no default — a missing value causes a plan-time error
    - _Requirements: 10.4_
  - [ ] 7.2 Implement Lambda execution role in `modules/iam/main.tf`:
    - `aws_iam_role` with trust policy allowing `lambda.amazonaws.com` only (exactly one principal, no wildcards, no conditions)
    - `aws_iam_role_policy` inline policy granting exactly `dynamodb:UpdateItem` and `dynamodb:GetItem` scoped strictly to `var.dynamodb_table_arn` (no wildcard resource ARN)
    - `aws_iam_role_policy_attachment` attaching the AWS-managed `AWSLambdaBasicExecutionRole` policy ARN
    - _Requirements: 10.1, 10.2, 10.3_
  - [ ] 7.3 Implement GitHub Actions OIDC provider and deployment role in `modules/iam/main.tf`:
    - `aws_iam_openid_connect_provider` for `token.actions.githubusercontent.com` with both thumbprints: `6938fd4d98bab03faadb97b34396831e3780aea1` and `1c58a3a8518e8759bf075b76b750d4f2df264fcd`
    - `aws_iam_role` (deployment role) with trust policy: `sts:AssumeRoleWithWebIdentity`, `StringEquals` conditions on both `sub = "repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"` AND `aud = "sts.amazonaws.com"`
    - `aws_iam_role_policy` inline policy granting frontend CI/CD permissions: `s3:ListBucket` on `var.s3_origin_bucket_arn`, `s3:PutObject` and `s3:DeleteObject` on `${var.s3_origin_bucket_arn}/*`, `cloudfront:CreateInvalidation` on `var.cloudfront_distribution_arn`; plus Terraform state permissions: `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` on `var.state_bucket_arn` and `${var.state_bucket_arn}/*`, `dynamodb:GetItem`, `dynamodb:PutItem`, `dynamodb:DeleteItem` on `var.state_lock_table_arn`
    - _Requirements: 11.1, 11.2, 11.3, 11.4_
  - [ ] 7.4 Write `modules/iam/outputs.tf` exposing `lambda_execution_role_arn` and `deployment_role_arn`
    - _Requirements: 10.5, 11.5_

- [ ] 8. Complete cross-module wiring in `terraform/main.tf` and add FinOps budget resources
  - [ ] 8.1 Finalise all cross-module variable bindings in `terraform/main.tf`:
    - Pass `module.compute.dynamodb_table_arn`, `module.cdn.origin_bucket_arn`, `module.cdn.cloudfront_distribution_arn`, `module.state_backend.state_bucket_arn`, `module.state_backend.lock_table_name` (as ARN) into `module.iam`
    - Pass `module.iam.lambda_execution_role_arn` into `module.compute`
    - Pass `module.cdn.cloudfront_domain_name` and `module.cdn.acm_validation_options` into `module.dns`
    - _Requirements: 2.2_
  - [ ] 8.2 Add `aws_sns_topic` and `aws_sns_topic_subscription` (email protocol) to `terraform/main.tf`, sourcing the email from `var.notification_email` (`sensitive = true`)
    - _Requirements: 13.5_
  - [ ] 8.3 Add `aws_sns_topic_policy` to `terraform/main.tf` allowing the `budgets.amazonaws.com` service principal to publish to the SNS topic
    - _Requirements: 13.5_
  - [ ] 8.4 Add `aws_budgets_budget` to `terraform/main.tf`:
    - `budget_type = "COST"`, `limit_amount = "6.00"`, `limit_unit = "USD"`, `time_unit = "MONTHLY"` — no service-level filter (account-wide scope)
    - Two `notification` blocks: actual costs at threshold `35` percent (GREATER_THAN), and forecasted costs at threshold `100` percent (GREATER_THAN), both publishing to the SNS topic ARN
    - _Requirements: 13.1, 13.2, 13.3, 13.4_
  - [ ] 8.5 Write `terraform/outputs.tf` with all root-level outputs; any output that references a sensitive variable or propagates a sensitive value MUST include `sensitive = true`
    - _Requirements: 14.3_

- [ ] 9. Checkpoint — full root validate and plan dry-run
  - Run `terraform fmt -check -recursive` and resolve any formatting issues
  - Run `terraform validate` and resolve all schema, type, and reference errors
  - Confirm all module input/output bindings are satisfied with no unresolved references
  - Ask the user if any questions arise before continuing.

- [ ] 10. Author GitHub Actions Terraform CI/CD pipeline (`terraform-cicd.yml`)
  - [ ] 10.1 Create `.github/workflows/terraform-cicd.yml`:
    - `on.push`: `branches: [main]`, `paths: ['terraform/**']`
    - `on.pull_request`: `branches: [main]`, `paths: ['terraform/**']`
    - Top-level `permissions: id-token: write, contents: read, pull-requests: write`
    - Job-level `defaults.run.working-directory: terraform`
    - `actions/checkout@v4` and `hashicorp/setup-terraform@v3` with `terraform_version: "~> 1.9"` steps
    - _Requirements: 12.6_
  - [ ] 10.2 Add sequential quality-gate steps (in order, each exits immediately on failure):
    - `terraform fmt -check -recursive`
    - `Configure AWS Credentials (OIDC)` using `aws-actions/configure-aws-credentials@v4` with `role-to-assume: ${{ secrets.AWS_DEPLOYMENT_ROLE_ARN }}`, `aws-region: ap-south-1`, `role-session-name: terraform-${{ github.run_id }}`
    - `terraform init -input=false`
    - `terraform validate`
    - _Requirements: 12.1, 12.6_
  - [ ] 10.3 Add checkov security scan step after validate and before plan:
    - Install: `pip install "checkov>=3.2"` (quotes required for shell compatibility)
    - Scan: `checkov -d . --framework terraform --soft-fail-on MEDIUM,LOW --compact --output cli`
    - HIGH/CRITICAL findings cause non-zero exit and block apply; MEDIUM/LOW emit warning annotations only
    - _Requirements: 12.2, 12.3, 12.4_
  - [ ] 10.4 Add `terraform plan` step (PR events only, `if: github.event_name == 'pull_request'`):
    - `terraform plan -no-color -input=false`
    - Inject `TF_VAR_cloudflare_api_token`, `TF_VAR_aws_account_id`, `TF_VAR_notification_email` from GitHub encrypted secrets
    - Add `actions/github-script@v7` step to post (or overwrite) a `### Terraform Plan` PR comment using the plan step output; overwrite any existing comment from a previous run on the same PR
    - _Requirements: 12.5_
  - [ ] 10.5 Add `terraform apply -auto-approve -input=false` step (push to `main` only, `if: github.event_name == 'push' && github.ref == 'refs/heads/main'`):
    - Same `TF_VAR_*` secret injections as the plan step
    - Confirm no static `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` values appear anywhere in the workflow file
    - _Requirements: 12.6_

- [ ] 11. Add post-apply smoke test step to `terraform-cicd.yml`
  - [ ] 11.1 Add an AWS CLI smoke-test step running after `terraform apply` on push to `main`, executing all seven checks:
    - S3 Block Public Access on origin bucket: `aws s3api get-public-access-block --bucket <BUCKET>` — all 4 flags must be `true`
    - S3 versioning on origin bucket: `aws s3api get-bucket-versioning --bucket <BUCKET>` — `Status: Enabled`
    - CloudFront HTTPS enforcement: `curl -sI http://vikram-sre.dev | grep -i location` — expect `301` redirect to `https://`
    - ACM certificate status: `aws acm describe-certificate --certificate-arn <ARN> --region us-east-1` — `Status: ISSUED`
    - DynamoDB PITR on `visitor-count`: `aws dynamodb describe-continuous-backups --table-name visitor-count` — `PointInTimeRecoveryStatus: ENABLED`
    - Lambda runtime: `aws lambda get-function-configuration --function-name <FUNC>` — `Runtime: python3.12`
    - OIDC provider thumbprints: `aws iam get-open-id-connect-provider --open-id-connect-provider-arn <ARN>` — both thumbprints present
    - _Requirements: 3.1, 3.4, 5.1, 4.2, 7.4, 8.1, 11.1_
  - [ ] 11.2 Add IAM policy simulation commands to the same post-apply step:
    - `aws iam simulate-principal-policy` to verify Lambda execution role allows `dynamodb:UpdateItem` and `dynamodb:GetItem` on the visitor-count table ARN, and is denied `dynamodb:DeleteTable`
    - `aws iam simulate-principal-policy` to verify deployment role allows `s3:PutObject` on the origin bucket, and is denied `s3:DeleteBucket`
    - _Requirements: 10.1, 10.2, 11.2, 11.3_

- [ ] 12. Add inline checkov suppression comments for documented architectural waivers
  - For each checkov finding that represents an intentional architectural decision, add an inline `# checkov:skip=CKV_ID:Reason` comment in the relevant `.tf` file; each suppression MUST reference the justifying ADR or FinOps constraint
  - Suppressions to add (based on design testing strategy — verify against actual checkov output and adjust CKV IDs as needed):
    - [ ] 12.1 `CKV_AWS_86` / `CKV_AWS_68` — CloudFront logging and WAF not attached: skip with reason referencing FinOps hard cap ($6/mo) and ADR 0002
    - [ ] 12.2 `CKV_AWS_116` — Lambda DLQ not configured: skip with reason referencing visitor-counter idempotency design and ADR 0001
    - [ ] 12.3 `CKV_AWS_50` — Lambda X-Ray tracing not enabled: skip with reason referencing FinOps hard cap
    - [ ] 12.4 `CKV_AWS_18` — S3 access logging on origin bucket: skip with reason referencing CloudFront access logs as the logging layer and FinOps constraint
    - [ ] 12.5 `CKV_AWS_52` — S3 MFA delete: skip with reason referencing operational overhead and FinOps single-account constraint
  - _Requirements: 12.3_

- [ ] 13. Update `docs/RUNBOOK.md` with IaC bootstrap prerequisites section
  - Add a new section titled "IaC Bootstrap Prerequisites" to `docs/RUNBOOK.md` covering:
    - Step 1: Manually create the KMS key (`alias/terraform-state`) in `ap-south-1`
    - Step 2: Manually create the S3 state bucket (`zero-trust-rac-tfstate`) with SSE-KMS and versioning before `terraform init` is run for the first time
    - Step 3: Manually create the DynamoDB lock table (`zero-trust-rac-tfstate-lock`) with `LockID` partition key
    - Step 4: Run `terraform init` inside `terraform/` — the `backend "s3"` block will use the manually bootstrapped bucket
    - Step 5: After first `terraform apply`, confirm the SNS email subscription (one-time manual step to activate cost alerts)
    - State lock force-unlock procedure: `terraform force-unlock <LOCK_ID>` — use only when a failed apply leaves an orphaned lock
  - _Requirements: 13.5_

- [ ] 14. Final checkpoint — end-to-end validation
  - Run `terraform fmt -check -recursive` and resolve any formatting issues
  - Run `terraform validate` and confirm clean output
  - Run a local checkov scan: `checkov -d terraform/ --framework terraform --compact` — confirm all HIGH/CRITICAL findings are either resolved or suppressed with documented inline waivers
  - Confirm `terraform/terraform.tfvars.example` documents every required variable with a description and example value
  - Confirm `docs/RUNBOOK.md` includes the "IaC Bootstrap Prerequisites" section from task 13
  - Confirm no `*.tfvars`, `*.tfstate`, `*.tfstate.backup`, or `.terraform/` files are tracked by git
  - Ensure all validations pass; ask the user if any questions arise.

---

## Notes

- No tasks are marked with `*` (optional). This is a pure IaC feature — there are no property-based tests or unit tests applicable. Static analysis and post-apply CLI smoke tests provide the full test coverage.
- **Bootstrap chicken-and-egg:** The state backend S3 bucket, DynamoDB lock table, and KMS key must be created manually once before `terraform init` can reference the remote backend. This is a known constraint; see task 13 and the RUNBOOK.
- **Cross-module dependency resolution:** `modules/iam` consumes the DynamoDB table ARN (from `modules/compute`) and the CloudFront distribution ARN (from `modules/cdn`). `modules/compute` consumes the Lambda execution role ARN from `modules/iam`. This apparent circularity is resolved at the root level — Terraform evaluates all module outputs before resolving inputs, so no circular dependency exists at the graph level.
- **Sensitive value flow:** GitHub Secret → `TF_VAR_*` env var → `sensitive = true` Terraform variable → redacted in all plan/apply output. This path must never be broken.
- **`.terraform.lock.hcl`** should be committed for reproducible provider installs. Do not add it to `.gitignore`.
- **Checkov suppressions** must always be inline `# checkov:skip=CKV_ID:Reason` comments — never blanket-skip entire directories or files.

---

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["0.1", "0.2", "0.3", "0.4", "0.5"] },
    { "id": 1, "tasks": ["2.1", "3.1", "4.1", "7.1"] },
    { "id": 2, "tasks": ["2.2", "3.2", "3.3", "6.1"] },
    { "id": 3, "tasks": ["2.3", "2.4", "3.4", "6.2", "6.3", "7.2", "7.3"] },
    { "id": 4, "tasks": ["3.5", "3.6", "4.2", "4.3", "4.4", "6.4", "7.4"] },
    { "id": 5, "tasks": ["6.5", "6.6"] },
    { "id": 6, "tasks": ["8.1", "8.2", "8.3"] },
    { "id": 7, "tasks": ["8.4", "8.5", "10.1"] },
    { "id": 8, "tasks": ["10.2", "10.3"] },
    { "id": 9, "tasks": ["10.4", "10.5"] },
    { "id": 10, "tasks": ["11.1", "11.2"] },
    { "id": 11, "tasks": ["12.1", "12.2", "12.3", "12.4", "12.5"] },
    { "id": 12, "tasks": ["13"] }
  ]
}
```
