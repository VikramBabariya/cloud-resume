# Cloud Resume: Serverless Portfolio on AWS

## 1. Project Overview

This project is a serverless full-stack application that hosts my professional resume on AWS. It demonstrates the use of cloud-native architecture, automated quality checks, and advanced observability. The website includes a dynamic "visitor counter" that updates in real-time, utilizing a purely serverless backend, alongside a secure integration that cryptographically verifies and displays my AWS certification status dynamically.

**Live Demo:** [https://vb-web.in/]

---

## 2. Architecture

The solution uses a decoupled client-server architecture hosted entirely on AWS.

### Architecture Diagram

<img width="1830" height="434" alt="cloud-resume-acrch-diagram" src="https://github.com/user-attachments/assets/75f54e38-cb12-4b11-ad81-e708e63cba31" />

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

## 3. FinOps and Guardrails

To ensure this serverless application remains cost-effective and secure against denial-of-wallet attacks, strict cloud governance policies have been implemented:

- **Hard Billing Alarms:** AWS Budgets is configured with a strict $6.00 monthly limit.
- **Proactive Alerting:** Notifications are dispatched to the administrative email when actual costs exceed 35% of the budget, or when forecasted costs hit 100%.
- **Cost-Optimized Storage:** External API credentials required for the dynamic Lambda backend are stored using AWS SSM Parameter Store (SecureString) to leverage standard-tier free encryption, explicitly avoiding the recurring costs of AWS Secrets Manager.
- **Throttling:** The API Gateway is configured with rate limiting to drop malicious or runaway traffic spikes before they trigger excessive Lambda compute durations.

---

## 4. Tech Stack

| Domain                 | Technology / Service                                             |
| :--------------------- | :--------------------------------------------------------------- |
| **Frontend**           | HTML5, CSS3, JavaScript                                          |
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

## 5. Architecture Decisions

Detailed architectural choices are documented as Architecture Decision Records (ADRs) to maintain a clean history of technical tradeoffs.

- [ADR 0001: Compute Layer for Backend API](docs/adr/0001-serverless-compute-layer.md)
- [ADR 0002: Static Asset Delivery and Network Boundaries](docs/adr/0002-network-boundaries-and-cdn.md)
- [ADR 0003: DynamoDB vs. Relational Database (RDS)](docs/adr/0003-dynamodb-vs-rds.md)
- [ADR 0004: Credentials Storage for Dynamic Verification API](docs/adr/0004-dynamic-credential-storage.md)

---

## 6. Key Features & Implementation Details

### A. Performance & Global Scale

- **Ultra-Low Latency:** Utilizes CloudFront's global network of over 400+ Points of Presence (PoPs). A user in London and a user in Tokyo both load the site instantly from a local edge server rather than fetching from the origin S3 bucket every time.
- **Caching Strategy:** Optimized cache behaviors ensure static assets (images, CSS) are cached aggressively at the edge, while dynamic API calls bypass the cache for real-time accuracy.

### B. Secure Static Hosting

- **S3 Bucket Policies:** Configured to block public access, allowing read access _only_ via the CloudFront Origin Access Control (OAC). This prevents users from bypassing the CDN.
- **HTTPS Enforcement:** All traffic is forced over HTTPS using a custom SSL/TLS certificate managed by **AWS Certificate Manager (ACM)**.

### C. Serverless Backend (API & Database)

- **Cost Efficiency:** The architecture fits almost entirely within the AWS Free Tier. Lambda and DynamoDB only charge when code runs or data is accessed ("Pay-per-use"), meaning zero idle costs.
- **High Availability:** Unlike a traditional single-server setup, this architecture relies on managed services (Lambda, DynamoDB) that are inherently distributed across multiple Availability Zones (AZs) by AWS.
- **Atomic Counting:** Used DynamoDB `ADD` operations to handle concurrent site visitors accurately without race conditions.
- **Secure Third-Party API Integration:** The backend securely orchestrates external API calls to validate my AWS certification status in real-time. By storing the required API keys as KMS-encrypted SecureStrings in AWS SSM Parameter Store, the architecture guarantees that no sensitive credentials are ever exposed to the frontend or hardcoded into the compute layer.

### D. Quality Assurance & Formatting

- **Automated Formatting:** **Prettier** is configured to ensure consistent code style across HTML, CSS, and JS files.
- **Git Hooks:** **Husky** is implemented to run pre-commit hooks. This prevents unformatted code from being committed to the repository, ensuring a clean codebase.

### E. Observability & Monitoring

To ensure system reliability and ease of debugging, a robust observability strategy was implemented:

- **Dashboards:** A custom **CloudWatch Dashboard** aggregates key metrics (API Latency, Visitor Count, Error Rates) into a single visual pane.
- **Canary Synthetics:** **CloudWatch Synthetics** (Canary) is deployed to run scheduled heartbeat scripts. This simulates user traffic to verify that the website endpoint is reachable and the API is responsive.
- **Distributed Tracing:** **AWS X-Ray** is enabled to visualize the request path and identify bottlenecks.
- **Structured Logging:** **CloudWatch Logs** capture execution details from the Lambda function.

---

## 7. Security & IAM

This project enforces strict cloud security boundaries, including least-privilege IAM roles, Cross-Origin Resource Sharing (CORS) restrictions, and rigorous cost-control mechanisms to minimize the blast radius of potential security incidents.

For a deep dive into the IAM policies, network boundaries, and security implementation, please refer to the detailed [Security Documentation](docs/SECURITY.md).

---

## 8. Automation & CI/CD Pipeline

The project utilizes **GitHub Actions** for continuous integration and deployment.

### Workflow Steps:

1.  **Checkout Code:** Pulls the latest repository code.
2.  **Formatting Check:** Runs the Prettier check. If the code does not meet style guidelines, the build fails.
3.  **Deploy:**
    - Syncs frontend assets to the S3 bucket.
    - Invalidates the CloudFront cache to ensure immediate content updates.
    - Updates the Lambda functions (both the Visitor Counter and the Credential Validator) via AWS CLI commands to ensure the backend is running the latest deployment package.

---

## 9. Deployment & Runbook

The step-by-step infrastructure provisioning guide, including manual ClickOps instructions, architectural flow, and conceptual bridges to Infrastructure as Code (Terraform), has been extracted to a dedicated runbook for incident response and deployment clarity.

Please refer to the [Deployment Runbook](docs/RUNBOOK.md) for full execution steps.

---

## 10. How to Run Locally (Development)

Since this project relies on AWS services (DynamoDB, API Gateway), strictly "local" development requires mocking these services or connecting to the live cloud resources from your local machine.

**Prerequisites:**

- Node.js & npm (for Prettier/Husky).
- Python 3.x (for Backend logic).
- AWS CLI configured (if running backend scripts against live AWS).
- Local `.env` file or AWS CLI configured with SSM access (to mock the external credential API key for the validation function).

### Step 1: Clone the Repository

```bash
git clone https://github.com/VikramBabariya/cloud-resume.git
cd cloud-resume-challenge
```

### Step 2: Install Frontend Dependencies

```bash
npm install
# This installs Prettier and sets up Husky hooks automatically
```

### Step 3: Run the Frontend

```
# You can utilize some local http server to open index.html file in the browser
```

## 11. Future Improvements

- Migrate manual infrastructure setup to Terraform or AWS CDK for full Infrastructure as Code (IaC).
- Implement a Dark/Light mode toggle for the UI.
- Add authentication for an admin dashboard to view detailed visitor analytics.
