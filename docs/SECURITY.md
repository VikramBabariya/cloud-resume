# Security Posture & Zero-Trust Architecture

This document outlines the security architecture, threat mitigation strategies, and operational safeguards governing the "Zero-Trust RaC Platform". The infrastructure is engineered to comply with **SRE Maturity Level 3** standards, prioritizing **Blast Radius Containment**, strict transit encryption, and continuous cost governance.

## Core Security Pillars

### 1. Edge-Network Zero-Trust & HSTS Enforcement

To guarantee the cryptographic integrity of all data-in-transit, the platform's public ingress boundary is strictly anchored to the `vikram-sre.dev` domain.

- **HSTS Preload:** The `.dev` Top-Level Domain acts as a hardcoded security perimeter. It natively enforces HTTP Strict Transport Security (HSTS), mathematically guaranteeing that client browsers cannot connect to the CloudFront CDN over unencrypted protocols, eliminating man-in-the-middle (MitM) downgrade attacks.
- **TLS Termination:** All encrypted traffic is terminated at the CloudFront edge network utilizing AWS Certificate Manager (ACM).

### 2. Identity Governance & Blast Radius Containment

Access to AWS resources is governed by a strict adherence to the **Principle of Least Privilege (PoLP)** across both automated pipelines and serverless compute layers.

- **OIDC Federated Identity:** Long-lived AWS IAM Access Keys are strictly prohibited. The GitHub Actions CI/CD runner authenticates via an AWS OpenID Connect (OIDC) Identity Provider, assuming a short-lived, ephemeral STS session token to mutate infrastructure, ensuring absolute **Blast Radius Containment**. The deployment role trust policy is declared in Terraform (`modules/iam`) with the `sub` claim locked to `repo:VikramBabariya/zero-trust-rac-platform:ref:refs/heads/main` and `aud = "sts.amazonaws.com"` — both enforced as `StringEquals` conditions. This makes the trust policy constraint version-controlled, peer-reviewed via pull request, and auditable in Git history; any attempt to widen the trust boundary (e.g., wildcard branch or cross-repository claim) requires an explicit, reviewable code change.
- **Serverless Compute Scoping:** The Visitor Counter Lambda execution role strictly allows `dynamodb:UpdateItem` and `dynamodb:GetItem` actions. This IAM policy is firmly scoped to the specific Amazon Resource Name (ARN) of the DynamoDB table, ensuring zero lateral movement capabilities.

### 3. Deployment Idempotency & Artifact Hygiene

The deployment architecture mathematically prevents supply chain pollution and orphaned infrastructure states.

- **Storage-Layer PoLP:** The CI/CD pipeline enforces **Artifact Hygiene** by exclusively targeting the compiled `./dist` directory during deployment.
- **State Synchronization:** Deployments utilize the `aws s3 sync --delete` command. This **Idempotent** operation guarantees the AWS S3 origin remains a perfect, 1:1 mirror of the validated Git repository, physically preventing raw backend scripts or stale data contracts from leaking to the public internet.

### 4. FinOps Guardrails & Layer 7 Abuse Mitigation

To defend against Layer 7 Denial-of-Wallet (DoW) attacks and ensure lean operational sustainability, rigorous FinOps mechanisms are hardcoded into the platform.

- **CORS Restrictions:** The API Gateway enforces strict Cross-Origin Resource Sharing (CORS) rules, rejecting unauthorized invocations and ensuring the backend API can only be successfully called by the legitimate `vikram-sre.dev` frontend domain.
- **Proactive Budget Alarms:** AWS CloudWatch Billing Alarms are firmly tied to a strict $6.00 monthly budget threshold. Automated notifications are dispatched to the administrative email immediately when actual costs exceed 35% of the budget, or when forecasted costs hit 100%, enabling rapid **MTTR** for anomalous compute spikes.

### 5. Infrastructure-as-Code Security Controls

All AWS and Cloudflare resources are declared in Terraform (under `terraform/`) and provisioned exclusively through the `terraform-cicd.yml` pipeline. The following controls are enforced at the IaC layer.

- **Remote state encryption:** Terraform state is stored in an S3 bucket with SSE-KMS encryption and versioning enabled. A bucket policy denies any `s3:PutObject` request that does not carry the `x-amz-server-side-encryption: aws:kms` header, ensuring every state write is encrypted at rest regardless of the caller's client-side configuration.
- **State access control:** The state S3 bucket and DynamoDB lock table (`zero-trust-rac-tfstate-lock`) are accessible exclusively to the OIDC deployment role. All four S3 Block Public Access settings are enabled on the state bucket; no public access path exists. Concurrent `terraform apply` runs are serialised by DynamoDB state locking (`LockID` partition key), preventing state corruption.
- **Shift-left IaC scanning:** `checkov >= 3.2` runs as a required gate in the pipeline after `terraform validate` and before any `terraform plan` or `terraform apply`. HIGH and CRITICAL severity findings cause a non-zero exit code and block the apply step entirely. MEDIUM/LOW findings are emitted as non-blocking warning annotations. Intentional waivers (e.g., no CloudFront WAF due to the $6/mo FinOps hard cap) are documented as inline `# checkov:skip=CKV_ID:Reason` comments in the relevant `.tf` file, referencing the applicable ADR, making every suppression auditable in source control.
- **Provider-level default tags:** Both AWS provider blocks (primary `ap-south-1` and the `us-east-1` alias for ACM) declare a `default_tags` block that stamps every taggable AWS resource with `Project`, `Environment`, `ManagedBy = "terraform"`, `Owner`, and `Repository`. Resources provisioned outside Terraform will lack these tags, making them immediately identifiable as drift in the AWS Console and Cost Explorer. This is a passive, zero-cost drift-detection signal that requires no additional tooling.
- **Sensitive variable governance:** No secrets or sensitive values are written to any `.tf` or `.tfvars` file committed to the repository. All sensitive inputs flow through a single, auditable path: `GitHub Encrypted Secret → TF_VAR_* environment variable → sensitive = true Terraform variable → redacted in plan/apply output`. The `terraform/` directory `.gitignore` unconditionally excludes `*.tfvars`, `*.tfstate`, and `*.tfstate.backup`, preventing accidental secret or state exposure regardless of future workflow changes.

## Vulnerability Reporting & Responsible Disclosure

As an active DevSecOps portfolio project, security research and vulnerability discovery are welcomed. To ensure **Artifact Hygiene** and maintain rapid remediation timelines, please adhere to the following disclosure process:

- **Reporting Protocol:** If you discover a vulnerability within the infrastructure-as-code, CI/CD pipeline, or application logic, please do not open a public GitHub Issue.
- **Action:** Submit a private vulnerability report via GitHub Security Advisories associated with this repository, or contact the maintainer directly via the professional channels linked on `vikram-sre.dev`.
- **Remediation SLA:** As part of the platform's SRE operational baseline, all validated vulnerabilities will be patched utilizing the automated, **Zero-Downtime** release pipeline.
