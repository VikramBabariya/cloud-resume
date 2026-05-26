# ADR 0004: Credentials Storage for Dynamic Verification API

**Date:** 2026-05-26
**Status:** DEPRECATED / ABANDONED (Superseded by Pre-Implementation Audit)
**Epic:** Credential Validator Feature
**Primary Driver:** SRE "Fail Fast" Principle & Dependency Risk

## Context

The serverless web enhancement requires fetching live AWS certification status from an external provider. This requires the backend compute layer to securely access an API key. Hardcoding this key into the Lambda function or storing it in plaintext environment variables is a critical security vulnerability.

## Options Considered

- **AWS Secrets Manager:** Offers native secret rotation and KMS encryption. Cost: $0.40 per secret/month.
- **AWS Systems Manager (SSM) Parameter Store (SecureString):** Offers KMS encryption. No native automated rotation. Cost: Free (Standard Tier).

## Decision

We will adopt AWS SSM Parameter Store using the `SecureString` parameter type.

## Security and Infrastructure Critique

- **Cost Control:** This decision eliminates recurring monthly costs, keeping the serverless architecture strictly within the Free Tier.
- **Encryption at Rest:** The API key will be encrypted using an AWS Key Management Service (KMS) managed key.
- **Network Boundaries:** Traffic between Lambda and SSM will remain within the AWS network backbone.
- **Least-Privilege IAM:** The executing Lambda function will be provisioned with a strict IAM policy granting `ssm:GetParameter` access _only_ to the specific Resource ARN of this credential. General `ssm:*` access is strictly prohibited.

## Consequences

We achieve a zero-trust credential storage mechanism at zero cost. We accept the tradeoff of manual key rotation, which is acceptable because the external validation provider does not enforce a strict 30-day rotation mandate.

---

## Deprecation Notice & Post-Mortem SRE Pivot

**Architectural State (2026-05-26):** This architectural decision has been formally **DEPRECATED**. A mandatory Pre-Implementation Discovery Audit revealed a High-Severity Dependency Blocker: the target external API (Credly) restricts programmatic credential generation strictly to Enterprise Organization/Admin accounts, rendering serverless integration for an individual account fundamentally unviable.

In strict adherence to DevSecOps **"Fail Fast"** methodologies and **SRE Maturity Level 3** standards, the surrounding epic was immediately aborted prior to infrastructure provisioning. This Shift-Left intervention successfully optimized **MTTE** (Mean Time To Evaluation) by preventing sunk engineering costs and preserved our **Zero-Trust Blast Radius Containment** strategy by avoiding the deployment of dormant, orphaned cloud resources. The engineering velocity has been strategically pivoted toward codified FinOps governance and CI/CD observability to further harden the platform.
