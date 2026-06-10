# ADR 0007: GitHub Actions Authentication via AWS OpenID Connect (OIDC)

## Status

Accepted

## Context

The Zero-Trust RaC Platform requires an automated CI/CD pipeline (GitHub Actions) to deploy compiled frontend artifacts (`./dist`) to an AWS S3 Origin and invalidate the CloudFront CDN cache.

The legacy configuration utilized static, long-lived AWS IAM User credentials (`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`) stored as GitHub Secrets.

From a DevSecOps and Site Reliability Engineering (SRE) perspective, long-lived credentials present a critical, unacceptable security vulnerability. If these static keys are leaked, scraped, or compromised, an attacker gains indefinite, persistent access to the AWS environment, leading to potential data exfiltration or denial-of-wallet attacks. The management of these keys also introduces operational overhead regarding mandatory 90-day cryptographic rotation.

## Decision

We will entirely deprecate the use of long-lived IAM User credentials for pipeline deployments. Instead, we will implement **Zero-Trust Identity Federation** utilizing an AWS IAM OpenID Connect (OIDC) Identity Provider.

GitHub Actions will authenticate to AWS dynamically by requesting a short-lived Security Token Service (STS) credential.

### Security & DevSecOps Constraints

To prevent the "Confused Deputy" vulnerability and enforce strict Zero-Trust boundaries, the following architectural constraints are mandated:

1. **Strict Subject (`sub`) Bounding:** The AWS IAM Role Trust Policy must explicitly restrict the `sts:AssumeRoleWithWebIdentity` action. It will only trust tokens originating specifically from the `VikramBabariya/zero-trust-rac-platform` repository, and strictly from the `main` branch.
2. **Ephemeral Access:** The assumed STS token will have a maximum session duration of 1 hour, mathematically eliminating the risk of long-term credential leakage.
3. **IAM Least Privilege:** The IAM Role assumed by the pipeline will **not** possess `AdministratorAccess`. It will be governed by an inline policy strictly scoped to:
   - `s3:ListBucket`, `s3:PutObject`, and `s3:DeleteObject` targeting _only_ the specific production S3 Bucket ARN.
   - `cloudfront:CreateInvalidation` targeting _only_ the specific production CloudFront Distribution ARN.

## Consequences

### Positive

- **Elimination of Static Keys:** Mathematically prevents the leakage of static AWS access keys, radically shrinking the project's attack surface.
- **Blast Radius Containment:** In the event of a GitHub repository compromise, the attacker's access is restricted to a 1-hour window and strictly limited to updating a single S3 bucket and CloudFront cache.
- **Operational Maturity:** Demonstrates enterprise-grade DevSecOps capabilities, aligning perfectly with modern AWS Well-Architected Framework security pillars.

### Negative

- **Implementation Complexity:** Introduces initial friction during the cloud provisioning phase, as establishing the OIDC Identity Provider and crafting the exact IAM Trust Policy JSON is significantly more complex than generating a static IAM User key.
