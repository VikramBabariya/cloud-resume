# Zero-Trust RaC Platform

> An SRE-hardened Zero-Trust RaC Platform leveraging OIDC federation and idempotent CI/CD to mathematically enforce blast radius containment and the Principle of Least Privilege (PoLP) at the edge.

## Executive Overview

This project is a fully automated, serverless full-stack application hosting a professional web portfolio on AWS. It demonstrates enterprise-grade cloud-native architecture, automated Site Reliability Engineering (SRE) quality gates, and advanced observability. The frontend utilizes a "Resume-as-Code" methodology for deterministic artifact compilation, while the backend features a purely serverless real-time visitor counter.

**Live Production Environment:** [https://vikram-sre.dev/](https://vikram-sre.dev/)

---

## Core Architectural Highlights (SRE & DevSecOps)

This project transcends a standard static website by operating as a fully automated **"Resume-as-Code" (RaC)** platform. The CI/CD deployment pipeline is engineered to enforce strict quality gates, guaranteeing deterministic and idempotent artifact generation prior to AWS synchronization.

- **Edge-Network Zero-Trust Ingress**
  - _Implementation:_ Authoritative DNS is consolidated via Cloudflare utilizing root-level **CNAME Flattening**. Traffic operates strictly via **DNS Only (Grey Cloud)** routing. The cryptographic TLS handshake and **HSTS** enforcement are executed natively at the AWS CloudFront Global CDN boundary utilizing AWS Certificate Manager (ACM).
  - _Strategic Value:_ This eliminates multi-vendor DNS propagation latency and explicitly mitigates Layer 7 interception threats before traffic reaches the CloudFront CDN, maximizing **MTTE** by signaling an enterprise-grade security posture and mathematical transit encryption to evaluating stakeholders.
- **Zero-Trust Identity Federation & Non-Repudiation**
  - _Implementation:_ Long-lived AWS IAM Access Keys have been strictly deprecated. The GitHub Actions CI/CD runner authenticates against AWS utilizing an OpenID Connect (OIDC) Identity Provider to assume a short-lived, ephemeral STS session token.
  - _Strategic Value:_ This Zero-Trust architecture mathematically enforces **Blast Radius Containment**; in the event of a runner compromise, the credential automatically expires. Furthermore, dynamic STS session naming (via GitHub Run IDs) guarantees absolute **Non-Repudiation**, ensuring every deployment mutation is cryptographically traceable within AWS CloudTrail.
- **Shift-Left Quality Gates & The "Fail Fast" Principle**
  - _Implementation:_ The pipeline explicitly decouples data (`resume.yaml`) from presentation. Before the Python SSG build engine compiles the artifact, the data layer undergoes rigorous local and CI/CD validation utilizing `yamllint`, `ajv-cli` (JSON Schema semantic validation), and Prettier.
  - _Strategic Value:_ Enforcing these Shift-Left Quality Gates applies the SRE **"Fail Fast"** principle. By terminating the build pipeline within seconds upon detecting a malformed data contract or syntax error, we preserve CI/CD compute budgets and drastically lower the **Mean Time To Recovery (MTTR)**.
- **Idempotent Deployment & Artifact Hygiene**
  - _Implementation:_ The deployment stage exclusively targets the compiled `./dist` directory utilizing the `aws s3 sync --delete` command against the origin S3 bucket.
  - _Strategic Value:_ This strict enforcement of Idempotency guarantees **Artifact Hygiene**. By mathematically ensuring the S3 bucket is a perfect, 1:1 mirror of the validated build, we uphold the **Principle of Least Privilege (PoLP)** at the storage layer, physically preventing raw backend Python scripts or YAML data from ever leaking to the public internet boundary.
- **Performance Engineering & Zero-Downtime Delivery**
  - _Implementation:_ The custom Python compilation engine performs Critical CSS Injection directly into the HTML `<head>`, eliminating render-blocking network requests. Post-deployment, the pipeline executes a mandatory `cloudfront create-invalidation` command.
  - _Strategic Value:_ This ensures top-tier **Time To First Contentful Paint (TTFCP)** performance metrics. The automated CDN invalidation guarantees a **Zero-Downtime Deployment** experience, forcing global edge locations (e.g., Mumbai, Hyderabad) to instantly serve the freshest artifact to end-users without manual intervention.

---

## System Architecture & Data Flow

The solution relies on a highly decoupled client-server architecture hosted entirely on AWS, utilizing API Gateway to securely proxy requests to backend microservices.

![architecture-diagram](/docs/architecture/export/system-design.png)
_(Diagram source maintained via Diagrams as Code in `/docs/architecture/source`)_

### Operational Workflows

**Flow A: The Visitor Counter (Data Mutation)**

1. **Frontend:** Static files are served globally via **CloudFront CDN** (enforcing HTTPS via **ACM**) from a strictly private **S3 Bucket** utilizing Origin Access Control (OAC).
2. **Compute & Storage:** JavaScript triggers an API call to **API Gateway**, which invokes a Python **Lambda function** to execute an atomic `ADD` operation against an On-Demand **DynamoDB** table, preventing concurrent race conditions.

**Flow B: Zero-Trust CI/CD Deployment (Automation)**

1. **Federated Authentication:** The `.github/workflows/front-end-cicd.yml` pipeline assumes an ephemeral deployment role via the AWS OIDC Identity Provider.
2. **Immutable Delivery:** The pipeline executes the SRE quality gates, compiles the HTML artifact, synchronizes exclusively the `./dist` folder to the S3 origin, and programmatically purges the CloudFront edge cache.

---

## 📉 FinOps & Cloud Governance

Enterprise-grade architecture must respect lean economics. This platform is governed by strict AWS CloudWatch and AWS Budgets alarms, hard-capping maximum monthly exposure to **$6.00 USD (approx. ₹500 INR)**.

By leveraging Cloudflare's zero-markup registrar and consolidating authoritative DNS, we eliminated AWS Route 53 hosted zone fees, reducing the foundational Layer 7 routing TCO to $0.00/month. Furthermore, API Gateway is configured with rate limiting to drop malicious traffic spikes before they trigger excessive Lambda compute durations, protecting against Denial-of-Wallet attacks.

---

## ⚙️ The DevSecOps Toolchain

| Domain                    | Technology / Service                                                                   |
| :------------------------ | :------------------------------------------------------------------------------------- |
| **Content Management**    | Resume-as-Code (YAML + Python/Jinja2 Static Site Generator)                            |
| **Frontend & Edge**       | AWS CloudFront, S3 (Origin Access Control), Cloudflare DNS (Authoritative, Grey Cloud) |
| **Serverless Backend**    | AWS Lambda (Python 3.12), AWS API Gateway (REST/HTTP)                                  |
| **Database & Secrets**    | Amazon DynamoDB (NoSQL)                                                                |
| **Identity & Security**   | AWS IAM (Strict **PoLP**), AWS STS, AWS OIDC, AWS ACM                                  |
| **CI/CD & Quality Gates** | GitHub Actions, `yamllint`, `ajv-cli` (Shift-Left Validation)                          |
| **Observability**         | AWS CloudWatch (Logs, Alarms, Dashboards), AWS X-Ray                                   |

---

## SRE Operational Runbook & Local Execution

To enforce the separation of concerns and maintain a clean executive summary, all granular deployment instructions, local development environment setups (the "Inner Loop"), and backend ClickOps provisioning steps (the "Outer Loop") are maintained in a dedicated SRE Runbook.

**[View the full SRE Operational Runbook here](docs/RUNBOOK.md)**

---

## Architecture Decision Records (ADRs)

Detailed architectural choices are documented as ADRs to maintain an immutable history of technical tradeoffs and system constraints.

- [ADR 0001: Compute Layer for Backend API](docs/adr/0001-serverless-compute-layer.md)
- [ADR 0002: Static Asset Delivery and Network Boundaries](docs/adr/0002-network-boundaries-and-cdn.md)
- [ADR 0003: DynamoDB vs. Relational Database (RDS)](docs/adr/0003-dynamodb-vs-rds.md)
- [ADR 0004: Credentials Storage for Dynamic Verification API](docs/adr/0004-dynamic-credential-storage.md)
- [ADR 0005: Resume as Code Methodology](docs/adr/0005-resume-as-code-methodology.md)
- [ADR 0006: Local Data Integrity Tooling (Shift-Left Quality Gates)](docs/adr/0006-local-data-integrity-tooling.md)
- [ADR 0007: GitHub Actions Authentication via AWS OpenID Connect (OIDC)](docs/adr/0007-aws-oidc-authentication.md)
- [ADR 0008: Strategic Domain Name Ingress and Registrar Procurement Selection](docs/adr/0008-domain-and-registrar-selection.md)

---

## Epic 5: Future Infrastructure-as-Code (IaC) Evolution

The next phase of architectural maturity focuses on entirely deprecating manual AWS backend provisioning in favor of declarative Infrastructure-as-Code.

- **Remote State Management:** Implement an encrypted S3 backend with DynamoDB state locking to securely manage `.tfstate` and prevent concurrent deployment corruption.
- **Declarative Compute & Data Layers:** Translate API Gateway, Lambda, DynamoDB, and IAM resources into modular Terraform (`.tf`) files.
- **Shift-Left IaC Scanning:** Integrate static analysis security testing (SAST) tools (e.g., `tfsec`, `checkov`) into the GitHub Actions pipeline to validate infrastructure security compliance prior to execution.
