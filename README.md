# Cloud Resume: Serverless Portfolio on AWS

## Executive Overview

This project is a fully automated, serverless full-stack application hosting a professional web portfolio on AWS. It demonstrates enterprise-grade cloud-native architecture, automated Site Reliability Engineering (SRE) quality gates, and advanced observability. The frontend utilizes a "Resume-as-Code" methodology for deterministic artifact compilation, while the backend features a purely serverless real-time visitor counter and a secure integration that cryptographically verifies AWS certification status dynamically.

**Live Production Environment:** [https://vb-web.in/](https://vb-web.in/)

---

## Core Architectural Highlights (SRE & DevSecOps)

This project transcends a standard static website by operating as a fully automated **"Resume-as-Code" (RaC)** platform. The CI/CD deployment pipeline is engineered to enforce strict quality gates, guaranteeing deterministic and idempotent artifact generation prior to AWS synchronization.

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

![cloud-resume-architecture-diagram](/docs/architecture/export/system-design.png)
_(Diagram source maintained via Diagrams as Code in `/docs/architecture/source`)_

### Operational Workflows

**Flow A: The Visitor Counter (Data Mutation)**

1. **Frontend:** Static files are served globally via **CloudFront CDN** (enforcing HTTPS via **ACM**) from a strictly private **S3 Bucket** utilizing Origin Access Control (OAC).
2. **Compute & Storage:** JavaScript triggers an API call to **API Gateway**, which invokes a Python **Lambda function** to execute an atomic `ADD` operation against an On-Demand **DynamoDB** table, preventing concurrent race conditions.

**Flow B: Dynamic Credential Validation (Secure Orchestration)**

1. **Compute & Security:** An asynchronous `fetch()` calls **API Gateway**, routing to a dedicated validation **Lambda function**.
2. **Secret Retrieval:** The Lambda assumes a least-privilege execution role to securely retrieve an encrypted external API key from **AWS SSM Parameter Store (SecureString)**.
3. **External Validation:** The function calls a third-party provider to cryptographically verify the AWS certification badge status and returns the formatted JSON payload.

**Flow C: Zero-Trust CI/CD Deployment (Automation)**

1. **Federated Authentication:** The `.github/workflows/front-end-cicd.yml` pipeline assumes an ephemeral deployment role via the AWS OIDC Identity Provider.
2. **Immutable Delivery:** The pipeline executes the SRE quality gates, compiles the HTML artifact, synchronizes exclusively the `./dist` folder to the S3 origin, and programmatically purges the CloudFront edge cache.

---

## FinOps & Cost Governance

To ensure this serverless application remains cost-effective and secure against denial-of-wallet attacks, strict cloud governance policies have been implemented:

- **Hard Billing Alarms:** AWS Budgets is configured with a strict ₹500 INR ($6.00 USD) monthly limit.
- **Proactive Alerting:** Notifications are dispatched to the administrative email when forecasted costs hit 100%.
- **Cost-Optimized Storage:** External credentials are stored using AWS SSM Parameter Store (SecureString) to leverage standard-tier free encryption, explicitly avoiding the recurring costs of AWS Secrets Manager.
- **Throttling:** API Gateway is configured with rate limiting to drop malicious traffic spikes before they trigger excessive Lambda compute durations.

---

## Technology Stack

| Domain                      | Technology / Service                                         |
| :-------------------------- | :----------------------------------------------------------- |
| **Content Management**      | Resume-as-Code (YAML + Python/Jinja2 Static Site Generator)  |
| **Cloud Storage & CDN**     | AWS S3 (Static Web Hosting), AWS CloudFront, AWS ACM         |
| **Compute & API (Backend)** | AWS Lambda (Python 3.12), AWS API Gateway (REST/HTTP)        |
| **Database & Secrets**      | AWS DynamoDB (NoSQL), AWS SSM Parameter Store (SecureString) |
| **Observability**           | AWS CloudWatch (Logs, Alarms, Dashboards), AWS X-Ray         |
| **CI/CD & Automation**      | GitHub Actions, AWS IAM (OIDC Federation)                    |

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

---

## Epic 5: Future Infrastructure-as-Code (IaC) Evolution

The next phase of architectural maturity focuses on entirely deprecating manual AWS backend provisioning in favor of declarative Infrastructure-as-Code.

- **Remote State Management:** Implement an encrypted S3 backend with DynamoDB state locking to securely manage `.tfstate` and prevent concurrent deployment corruption.
- **Declarative Compute & Data Layers:** Translate API Gateway, Lambda, DynamoDB, and IAM resources into modular Terraform (`.tf`) files.
- **Shift-Left IaC Scanning:** Integrate static analysis security testing (SAST) tools (e.g., `tfsec`, `checkov`) into the GitHub Actions pipeline to validate infrastructure security compliance prior to execution.
