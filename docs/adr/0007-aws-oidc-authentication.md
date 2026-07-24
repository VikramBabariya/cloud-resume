# ADR 0007: GitHub Actions Authentication via AWS OpenID Connect (OIDC)

## Status

Accepted

## Context

The Zero-Trust RaC Platform requires two automated CI/CD pipelines (GitHub Actions) to:

1. Deploy compiled frontend artifacts (`./dist`) to an AWS S3 Origin and invalidate the CloudFront CDN cache (`front-end-cicd.yml`).
2. Plan and apply Terraform infrastructure changes (`terraform-cicd.yml`).

The legacy configuration utilized static, long-lived AWS IAM User credentials (`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`) stored as GitHub Secrets.

From a DevSecOps and Site Reliability Engineering (SRE) perspective, long-lived credentials present a critical, unacceptable security vulnerability. If these static keys are leaked, scraped, or compromised, an attacker gains indefinite, persistent access to the AWS environment, leading to potential data exfiltration or denial-of-wallet attacks. The management of these keys also introduces operational overhead regarding mandatory 90-day cryptographic rotation.

## Decision

We will entirely deprecate the use of long-lived IAM User credentials for pipeline deployments. Instead, we will implement **Zero-Trust Identity Federation** utilizing an AWS IAM OpenID Connect (OIDC) Identity Provider.

GitHub Actions will authenticate to AWS dynamically by requesting a short-lived Security Token Service (STS) credential. Both pipelines share the same OIDC provider and deployment role but use different `role-session-name` values (`<repo-name>-<run_id>` for the frontend pipeline, `terraform-<run_id>` for the IaC pipeline) to distinguish sessions in CloudTrail.

### Security & DevSecOps Constraints

To prevent the "Confused Deputy" vulnerability and enforce strict Zero-Trust boundaries, the following architectural constraints are mandated:

1. **Two-Statement Trust Policy (`sub` Bounding):** The AWS IAM Role Trust Policy uses two separate `sts:AssumeRoleWithWebIdentity` statements to support both workflow event types emitted by GitHub Actions:

   | GitHub Event     | JWT `sub` Claim                                                   | Permitted Operations                        |
   | ---------------- | ----------------------------------------------------------------- | ------------------------------------------- |
   | `push` to `main` | `repo:VikramBabariya/zero-trust-rac-platform:ref:refs/heads/main` | `terraform apply`, S3 sync, CF invalidation |
   | `pull_request`   | `repo:VikramBabariya/zero-trust-rac-platform:pull_request`        | `terraform plan` only (read)                |

   Both statements enforce `StringEquals` on the `aud` claim (`sts.amazonaws.com`) to prevent cross-audience token reuse. A single-statement policy scoped only to `ref:refs/heads/main` blocks PR-triggered workflows from authenticating — this was discovered operationally (see [INC-002](../incidents/INC-002-oidc-pr-trust-policy-rejection.md)) and resolved by adding the `pull_request` statement. The `terraform apply` step in `terraform-cicd.yml` is additionally gated at the workflow level by `if: github.event_name == 'push' && github.ref == 'refs/heads/main'`, ensuring a PR token can never trigger a destructive apply even if it satisfies the trust policy.

2. **Ephemeral Access:** The assumed STS token will have a maximum session duration of 1 hour, mathematically eliminating the risk of long-term credential leakage.
3. **IAM Least Privilege:** The IAM Role assumed by the pipeline will **not** possess `AdministratorAccess`. Its inline policy is strictly scoped to the minimum permissions required for both pipelines:
   - **Frontend CI/CD:** `s3:ListBucket`, `s3:PutObject`, `s3:DeleteObject` targeting only the S3 origin bucket ARN; `cloudfront:CreateInvalidation` targeting only the CloudFront distribution ARN.
   - **IaC (Terraform):** `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` on the Terraform state bucket; `dynamodb:GetItem`, `dynamodb:PutItem`, `dynamodb:DeleteItem` on the state lock table; read-only refresh permissions for all managed resource types (CloudFront, ACM, Lambda, API Gateway, DynamoDB, IAM, SNS, Budgets, KMS).

The trust policy is declared in Terraform (`modules/iam/main.tf`) making every change to the trust boundary a reviewable pull request with a `terraform plan` diff posted as a PR comment.

## Consequences

### Positive

- **Elimination of Static Keys:** Mathematically prevents the leakage of static AWS access keys, radically shrinking the project's attack surface.
- **Blast Radius Containment:** In the event of a GitHub repository compromise, the attacker's access is restricted to a 1-hour window and strictly limited to the permissions declared in the deployment role's inline policy.
- **PR Plan Previews:** The `pull_request` trust policy statement enables the Terraform pipeline to run `terraform plan` on every PR and post the output as a comment, giving reviewers exact resource diffs before approving.
- **Version-Controlled Trust Boundary:** The trust policy is Terraform-managed — widening it (e.g., adding a wildcard `sub` claim or a new branch) requires an explicit, peer-reviewed code change. No console-level trust policy changes can persist without a matching Terraform commit.
- **Operational Maturity:** Demonstrates enterprise-grade DevSecOps capabilities, aligning perfectly with modern AWS Well-Architected Framework security pillars.

### Negative

- **Implementation Complexity:** Establishing the OIDC Identity Provider, crafting the trust policy JSON with correct `sub` claim formats, and validating both `push` and `pull_request` event flows is significantly more complex than generating a static IAM User key. The `pull_request` trust policy statement was discovered as a requirement through operational incident INC-002 rather than proactively.
- **Event-type-specific `sub` claims must be known upfront.** GitHub issues different `sub` values for different event types. Adding new trigger event types to a workflow (e.g., `workflow_dispatch`, `schedule`) may require additional trust policy statements.
