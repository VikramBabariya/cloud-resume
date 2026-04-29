# Cloud Resume: Serverless Portfolio on AWS

## Project Overview

This project is a serverless full-stack application that hosts my professional resume on AWS. It demonstrates the use of cloud-native architecture, automated quality checks, and advanced observability. The frontend utilizes a "Resume as Code" methodology for automated content compilation, while the backend features a purely serverless real-time visitor counter and a secure integration that cryptographically verifies my AWS certification status dynamically.

**Live Demo:** [https://vb-web.in/](https://vb-web.in/)

---

## Core Architectural Highlights (SRE & DevSecOps)

This project transcends a standard static website by operating as a fully automated **"Resume-as-Code" (RaC)** platform. The CI/CD deployment pipeline is engineered to enforce strict Site Reliability Engineering (SRE) quality gates, mathematically guaranteeing deterministic and idempotent artifact generation prior to AWS synchronization.

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

## Architecture

The solution uses a decoupled client-server architecture hosted entirely on AWS.

### Architecture Diagram

![cloud-resume-architecture-diagram](/docs/architecture/export/system-design.png)
_(Diagram source maintained via Diagrams as Code in `/docs/architecture/source`)_

### High-Level Workflow:

**Flow A: The Visitor Counter**

1.  **Frontend:** Static files (HTML, CSS, JS) are stored in an **S3 Bucket**.
2.  **Content Delivery:** **CloudFront** acts as a CDN to cache content globally and enforce HTTPS via an **ACM Certificate**.
3.  **DNS:** **Route 53** manages the domain name resolution.
4.  **Backend Trigger:** JavaScript on the frontend triggers an API call to **API Gateway**.
5.  **Compute:** API Gateway triggers a **Lambda function** (written in Python).
6.  **Database:** The Lambda function atomically updates and retrieves the visitor count from a **DynamoDB** table.

**Flow B: Dynamic Credential Validation**

1.  **Backend Trigger:** A separate asynchronous JavaScript `fetch()` call requests the credential status from **API Gateway**.
2.  **Compute & Security:** API Gateway routes the request to a dedicated **Lambda function**.
3.  **Secret Retrieval:** The Lambda function securely retrieves the external API key from **AWS SSM Parameter Store (SecureString)** using a strictly scoped, least-privilege IAM execution role.
4.  **External Validation:** Lambda calls the third-party certification provider to cryptographically verify the badge status and returns the formatted JSON payload to the frontend.

---

## FinOps and Guardrails

To ensure this serverless application remains cost-effective and secure against denial-of-wallet attacks, strict cloud governance policies have been implemented:

- **Hard Billing Alarms:** AWS Budgets is configured with a strict $6.00 monthly limit.
- **Proactive Alerting:** Notifications are dispatched to the administrative email when actual costs exceed 35% of the budget, or when forecasted costs hit 100%.
- **Cost-Optimized Storage:** External API credentials required for the dynamic Lambda backend are stored using AWS SSM Parameter Store (SecureString) to leverage standard-tier free encryption, explicitly avoiding the recurring costs of AWS Secrets Manager.
- **Throttling:** The API Gateway is configured with rate limiting to drop malicious or runaway traffic spikes before they trigger excessive Lambda compute durations.

---

## Tech Stack

| Domain                 | Technology / Service                                             |
| :--------------------- | :--------------------------------------------------------------- |
| **Frontend UI**        | HTML5, CSS3, JavaScript                                          |
| **Content Management** | Resume as Code (YAML + Python/Jinja2 Templating)                 |
| **Cloud Storage**      | AWS S3 (Static Website Hosting)                                  |
| **CDN & Security**     | AWS CloudFront, AWS Certificate Manager (ACM)                    |
| **DNS**                | AWS Route 53                                                     |
| **Compute (Backend)**  | AWS Lambda                                                       |
| **API Management**     | AWS API Gateway (REST/HTTP API)                                  |
| **Database**           | AWS DynamoDB (NoSQL)                                             |
| **Secrets Management** | AWS SSM Parameter Store (SecureString / KMS Encrypted)           |
| **Code Quality**       | Prettier, Husky                                                  |
| **Observability**      | AWS CloudWatch (Logs, Alarms, Dashboards, Synthetics), AWS X-Ray |
| **Version Control**    | Git & GitHub                                                     |
| **CI/CD**              | GitHub Actions                                                   |

---

## Architecture Decisions

Detailed architectural choices are documented as Architecture Decision Records (ADRs) to maintain a clean history of technical tradeoffs.

- [ADR 0001: Compute Layer for Backend API](docs/adr/0001-serverless-compute-layer.md)
- [ADR 0002: Static Asset Delivery and Network Boundaries](docs/adr/0002-network-boundaries-and-cdn.md)
- [ADR 0003: DynamoDB vs. Relational Database (RDS)](docs/adr/0003-dynamodb-vs-rds.md)
- [ADR 0004: Credentials Storage for Dynamic Verification API](docs/adr/0004-dynamic-credential-storage.md)
- [ADR 0005: Resume as Code Methodology](docs/adr/0005-resume-as-code-methodology.md)

---

## Key Features & Implementation Details

### A. Resume as Code (Data Decoupling)

- **Separation of Concerns:** Professional history and skills are stored in a version-controlled YAML data file. A Python-based Jinja2 templating engine dynamically compiles this data into the final HTML artifact during the CI/CD deployment. This entirely eliminates manual HTML editing for content updates, ensuring formatting consistency and reducing technical debt.
  _(The data schema strictly adheres to the JSON Resume standard. The raw data source can be found in `/data/resume.yaml`)_

### B. Performance & Global Scale

- **Ultra-Low Latency:** Utilizes CloudFront's global network of over 400+ Points of Presence (PoPs).
- **Caching Strategy:** Optimized cache behaviors ensure static assets (images, CSS) are cached aggressively at the edge, while dynamic API calls bypass the cache for real-time accuracy.

### C. Secure Static Hosting

- **S3 Bucket Policies:** Configured to block public access, allowing read access _only_ via the CloudFront Origin Access Control (OAC).
- **HTTPS Enforcement:** All traffic is forced over HTTPS using a custom SSL/TLS certificate managed by **AWS Certificate Manager (ACM)**.

### D. Serverless Backend (API & Database)

- **Cost Efficiency:** The architecture fits almost entirely within the AWS Free Tier.
- **High Availability:** Inherently distributed across multiple Availability Zones (AZs) by AWS.
- **Atomic Counting:** Used DynamoDB `ADD` operations to handle concurrent site visitors accurately without race conditions.
- **Secure Third-Party API Integration:** The backend securely orchestrates external API calls to validate my AWS certification status in real-time, retrieving credentials via KMS-encrypted SecureStrings.
- **Data Lifecycle & Threat Modeling:** The precise routing logic, payload transformations, and secure memory decryption sequences for both microservices are strictly mapped in the [Level 1 Data Flow Diagram (DFD)](docs/architecture/data-flow.md).

### E. Quality Assurance & Formatting

- **Automated Formatting:** **Prettier** is configured to ensure consistent code style.
- **Git Hooks:** **Husky** is implemented to run pre-commit hooks, preventing unformatted code from entering the repository.

### F. Observability & Monitoring

- **Dashboards:** A custom **CloudWatch Dashboard** aggregates key metrics.
- **Canary Synthetics:** **CloudWatch Synthetics** verifies endpoint reachability.
- **Distributed Tracing:** **AWS X-Ray** is enabled to visualize the request path.
- **Structured Logging:** **CloudWatch Logs** capture execution details.

---

## Security & IAM

This project enforces strict cloud security boundaries, including least-privilege IAM roles, Cross-Origin Resource Sharing (CORS) restrictions, and rigorous cost-control mechanisms. For a deep dive into the IAM policies, network boundaries, and security implementation, please refer to the detailed [Security Documentation](docs/SECURITY.md).

---

## Automation & CI/CD Pipeline

The project utilizes **GitHub Actions** for continuous integration, templating, and deployment.

### Workflow Steps:

1.  **Checkout Code:** Pulls the latest repository code.
2.  **Formatting & Linting:** Runs Prettier checks and validates the YAML data schema.
3.  **Compile Static Assets (Build):** Executes the Python/Jinja2 build script to merge the `resume.yaml` data into the HTML template, generating the immutable `index.html` artifact.
4.  **Deploy:**
    - Syncs the compiled frontend assets to the S3 bucket.
    - Invalidates the CloudFront cache to ensure immediate content updates.
    - Updates the Lambda functions via AWS CLI commands to ensure the backend is running the latest deployment package.

---

## Deployment & Runbook

The step-by-step infrastructure provisioning guide, including manual ClickOps instructions, architectural flow, and conceptual bridges to Infrastructure as Code (Terraform), has been extracted to a dedicated runbook for incident response.

Please refer to the [Deployment Runbook](docs/RUNBOOK.md) for full execution steps.

---

## Local Development & Compilation Engine

This project operates on a strict **"Resume as Code"** methodology. The frontend UI is treated as a stateless compilation target, generated dynamically by a custom Python Static Site Generator (SSG) to ensure absolute separation of concerns between data (`resume.yaml`) and presentation (`Jinja2`).

### System Requirements

To guarantee deterministic builds and prevent software supply chain pollution, local environments must strictly mirror the CI/CD pipeline. We enforce explicit minimum patch versions to eliminate "it works on my machine" anomalies and maintain a robust DevSecOps posture.

- **Python:** `>= 3.12.x`
- **Node.js:** `>= 24.13.x`
- **npm:** `>= 11.6.x`

### Step 1: Clone the Repository

```bash
git clone [https://github.com/VikramBabariya/cloud-resume.git](https://github.com/VikramBabariya/cloud-resume.git)
cd cloud-resume-challenge
```

### Step 2. Environment Initialization

Before compiling the artifact, you must initialize the isolated dependency sandboxes. Never install these tools globally.

```bash
# 1. Initialize the Python Virtual Environment (Prevents dependency hell)
python3 -m venv .venv
source .venv/bin/activate  # Windows: .\.venv\Scripts\Activate.ps1

# 2. Install Python Build Dependencies
pip install -r requirements.txt

# 3. Install Node.js Validation Tooling
npm install
```

### Step 3: SRE Quality Gates

To prevent malformed data from reaching the production S3 bucket, all configuration changes must pass a strict two-stage local validation gate.

```bash
# Executes yamllint (structural syntax) and ajv-cli (semantic schema validation)
npm run validate
```

- **Stage 1 (Syntax):** Enforces YAML 1.2 specifications and prevents indentation/spacing violations.
- **Stage 2 (Semantic):** Validates the data payload against the official `schema.json` contract (JSON Resume Standard), ensuring all required business logic fields exist before compilation.

### Step 3: Build and Run the Frontend

```bash
# Once validation passes, execute the build engine to merge the data layer with the presentation template.
python build.py

# To test the compiled artifact and asynchronous API fetches locally without triggering browser CORS restrictions, utilize Python's built-in HTTP server:
python -m http.server 8000
```

Navigate to http://localhost:8000 to verify the UI and telemetry integrations.

## Future Improvements

- Migrate manual infrastructure setup to Terraform or AWS CDK for full Infrastructure as Code (IaC).
- [Architectural Enhancement: Automated CI/CD Pipeline (GitOps)](https://github.com/VikramBabariya/cloud-resume/issues/5)
- Implement a Dark/Light mode toggle for the UI.
