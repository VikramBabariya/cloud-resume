# ADR 0009: Terraform IaC Adoption — Replacing ClickOps with Declarative Infrastructure

## Status

Accepted

## Context

All backend resources powering the Zero-Trust RaC Platform are currently provisioned manually through the AWS Management Console ("ClickOps"):

- **Storage & CDN:** S3 origin bucket, CloudFront distribution, ACM TLS certificate
- **Compute:** API Gateway HTTP API, Lambda (visitor counter, Python 3.12)
- **Data:** DynamoDB visitor-count table
- **Identity:** IAM execution role, IAM deployment role, GitHub Actions OIDC Identity Provider
- **DNS:** Cloudflare CNAME records for apex, `www`, and ACM validation

This approach introduces three compounding risks:

1. **No auditable change history.** Infrastructure mutations happen through the console with no version-controlled record of what changed, who changed it, or why. Any drift from the intended state is invisible until something breaks.
2. **Manual DNS intervention during DR.** Cloudflare records must be recreated by hand during a disaster-recovery event, extending RTO and introducing human error under pressure.
3. **No policy-as-code safety net.** There is no automated mechanism to detect security misconfigurations (public S3 bucket, overly broad IAM policy, missing encryption) before they reach production.

The current ClickOps workflow is documented in `docs/RUNBOOK.md` Section 5, but documentation is not enforcement. The platform has reached a maturity point where infrastructure must be treated as a first-class project artifact with the same quality gates applied to application code.

## Decision

Adopt **Terraform >= 1.9.0** as the single Infrastructure-as-Code tool for all AWS and Cloudflare resources, backed by a remote S3 + DynamoDB state backend.

The Terraform configuration will live under `terraform/` at the repository root and will be organised into five focused child modules:

| Module                  | Responsibility                                                      |
| ----------------------- | ------------------------------------------------------------------- |
| `modules/state-backend` | S3 state bucket (SSE-KMS, versioning), DynamoDB lock table          |
| `modules/cdn`           | S3 origin bucket (OAC), ACM certificate, CloudFront distribution    |
| `modules/compute`       | DynamoDB visitor-count table, Lambda function, API Gateway HTTP API |
| `modules/dns`           | Cloudflare CNAME records (apex, www, ACM validation)                |
| `modules/iam`           | Lambda execution role, GitHub OIDC provider, deployment role        |

Any addition of a new module beyond these five must be documented in a subsequent ADR before the module is created.

All IaC changes are gated by a new GitHub Actions pipeline (`terraform-cicd.yml`) running the following sequential quality gates: `terraform fmt → terraform validate → checkov >= 3.2 → terraform plan → terraform apply`.

## Alternatives Considered

### AWS CDK (Cloud Development Kit)

Rejected. CDK requires a Python (or TypeScript) runtime dependency and a separate synthesis step (`cdk synth`) that produces CloudFormation templates. This adds toolchain complexity to a project that already has Python pinned to a specific version for the Lambda runtime and build engine. A CDK upgrade or breaking change in the construct library could silently alter synthesised infrastructure. Terraform's declarative HCL is simpler to audit and has no synthesis intermediary.

### Pulumi

Rejected. Pulumi has a smaller community than Terraform, a thinner ecosystem of modules for the specific provider combination used here (AWS + Cloudflare), and no native checkov support. The `checkov` shift-left scanning requirement (Requirement 12) is a hard constraint; retrofitting a third-party Pulumi scanner would add friction with no architectural benefit.

### Manual CloudFormation

Rejected. CloudFormation is verbose, AWS-only (no Cloudflare provider), and requires managing change sets and stack drift manually. It offers no advantage over Terraform for this use case and would leave Cloudflare DNS outside the IaC boundary, perpetuating the manual DNS problem that motivated this decision.

## Consequences

### Positive

- **Auditable change history.** Every infrastructure mutation is a reviewed pull request with a `terraform plan` diff posted as a PR comment. CloudTrail and Terraform state together provide a complete, correlated audit trail.
- **Automated DR.** DNS records, CloudFront aliases, and ACM certificates are all reproduced from code with a single `terraform apply`. The manual DNS steps in `docs/RUNBOOK.md` Section 5 are fully superseded.
- **Shift-left security.** `checkov >= 3.2` runs as a required gate before every plan and apply. HIGH and CRITICAL findings block the pipeline. Intentional waivers are explicit inline `# checkov:skip` comments, making security trade-offs visible in source control.
- **Sensitive value governance.** All secrets (Cloudflare API token, AWS account ID, notification email) flow via `GitHub Secret → TF_VAR_* env var → sensitive = true Terraform variable → redacted plan/apply output`. No plaintext secrets can be committed.
- **`terraform/` becomes a first-class artifact.** The directory sits alongside `src/` and `data/` as a peer project concern, subject to the same review, formatting, and validation disciplines.

### Negative / Operational Overheads

- **One-time bootstrap sequence required.** The state backend (S3 bucket, DynamoDB table, KMS key) cannot manage itself — Terraform cannot store state before the state bucket exists. These three resources must be created manually in `ap-south-1` before `terraform init` is run for the first time. This bootstrap procedure is documented in `docs/RUNBOOK.md` as the "IaC Bootstrap Prerequisites" section.
- **ClickOps steps deprecated.** `docs/RUNBOOK.md` Section 5 ("Backend Resource Provisioning") is superseded by `terraform apply`. The original manual steps are retained as a historical reference but are marked deprecated. Engineers must not use them for new provisioning.
- **SNS subscription confirmation is manual.** After the first `terraform apply`, the Budget Alarm SNS email subscription requires a one-time manual confirmation click. This is an AWS constraint, not a Terraform limitation, and is documented as a post-apply prerequisite in the runbook.
- **State lock recovery requires manual intervention.** A failed `terraform apply` that does not cleanly release the DynamoDB lock must be resolved with `terraform force-unlock <LOCK_ID>`. This procedure is documented in the runbook alongside guidance to verify CloudTrail before force-unlocking.
