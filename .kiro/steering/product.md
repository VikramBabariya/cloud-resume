# Product: Zero-Trust RaC Platform

A production-grade, fully automated serverless portfolio platform hosted on AWS. It demonstrates enterprise cloud-native architecture using a **Resume-as-Code (RaC)** methodology — professional content lives in a version-controlled YAML file that is compiled into a static HTML artifact by a Python/Jinja2 build engine.

**Live site:** https://vikram-sre.dev/

## Core Capabilities

- **Resume-as-Code pipeline:** `data/resume.yaml` is the single source of truth. The build engine merges it with a Jinja2 template and injects Critical Path CSS inline to eliminate render-blocking requests.
- **Serverless visitor counter:** JavaScript calls API Gateway → Lambda (Python) → DynamoDB atomic `ADD`.
- **Zero-Trust CI/CD:** GitHub Actions authenticates to AWS via OIDC federation (no long-lived IAM keys). Deployments sync only `./dist` to S3 with `--delete` for artifact hygiene, then invalidate CloudFront.

## Key Design Principles

- **Shift-Left quality gates:** Validate data contract locally before building. Fail fast — a bad YAML commit must never reach S3.
- **Blast Radius Containment:** Short-lived STS tokens scoped to least privilege. Raw source files (YAML, Python) never reach the public internet boundary.
- **FinOps governance:** Infrastructure hard-capped at ₹500 INR/month (~$6 USD). API Gateway rate limiting guards against Denial-of-Wallet attacks.
- **Idempotency:** Every deployment produces the same artifact from the same input. `aws s3 sync --delete` ensures the bucket is always a 1:1 mirror of `./dist`.
