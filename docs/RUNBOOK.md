# Zero-Trust RaC Platform: Operational Runbook

## 1. System Design Implications (HLD/LLD) & Networking Principles

Before executing any provisioning steps, you must understand the data flow, network boundaries, and underlying principles of this architecture:

- **Public Boundary (RFC 1918 & NAT Consideration):** Traffic flows from the public internet via Cloudflare Authoritative DNS (utilizing CNAME Flattening) directly to the AWS CloudFront Edge network. The origin S3 bucket remains strictly private within the AWS network, accessible only via Origin Access Control (OAC). No public IP addresses are assigned to internal resources.
- **DNS Ingress & TLS Termination Governance:** Traffic routing is anchored to `vikram-sre.dev`. The `.dev` Top-Level Domain acts as a strict operational boundary, physically enforcing HSTS (HTTP Strict Transport Security) to cryptographically guarantee data-in-transit integrity prior to edge caching.
  - _SRE Traceability:_ Review [ADR 0008](adr/0008-domain-and-registrar-selection.md) for the complete FinOps procurement logic, Single-Provider Consolidation, and MTTE-optimization strategy governing this Layer 7 namespace.
- **API & Proxy Boundary:** API Gateway acts as the secure entry point, proxying HTTPS requests from the client browser to the appropriate backend microservice.
- **Flow A (Visitor Counter):** API Gateway invokes the Counter Lambda, which executes an atomic `ADD` operation against the DynamoDB data layer.
- **CI/CD Deployment Boundary (Zero-Trust):** Automated deployments are executed via GitHub Actions. Long-lived AWS IAM Access Keys are strictly prohibited. The runner authenticates dynamically using an AWS OpenID Connect (OIDC) Identity Provider to assume a short-lived, least-privilege IAM role.

## 2. FinOps Pre-Flight Check

**WARNING:** Do not proceed with AWS provisioning until you have verified your AWS Free Tier limits and established cost governance.

- Ensure an AWS Budgets hard alarm is set to **$6.00 USD (approx. ₹500 INR)**.
- Ensure billing alerts are configured to notify your administrative email at 50% and 100% of the forecasted budget.

## 3. Local Development & Validation (The Inner Loop)

This project utilizes a "Resume-as-Code" methodology. You must validate and compile the YAML data locally within heavily sandboxed environments before committing code.

### Prerequisites

- Node.js `>= 24.13.x` & npm `>= 11.6.x` (For JSON Schema validation)
- Python `>= 3.12.x` (For the SSG build engine and YAML structural linting)

### Step 3.1: Environment Initialization

Global package installations are prohibited to prevent supply chain pollution. Initialize local virtual environments and lockfiles.

```bash
# 1. Initialize the Python Virtual Environment
python3 -m venv .venv
source .venv/bin/activate  # Windows: .\.venv\Scripts\Activate.ps1

# 2. Install Python Build Dependencies
pip install -r requirements.txt

# 3. Install Node.js Validation Tooling Cleanly
npm ci
```

### Step 3.2: SRE Quality Gates (Shift-Left Testing)

Execute the local validation wrapper to test the data contract. If this fails, investigate the SRE error trace and do not commit.

```bash
# Enforce UI Formatting Consistency
npx prettier --check "**/*.{html,css,js}"

# Executes yamllint (structural syntax) and ajv-cli (semantic schema validation)
npm run validate
```

### Step 3.3: Compile the Frontend & Verify Locally

Execute the Python compiler to merge the validated data with the Jinja2 template and inject Critical Path CSS.

```bash
# Generate the dist/index.html artifact
python build.py

# Simulate the Edge Network locally (Bypasses local CORS restrictions)
python3 -m http.server 8000 --directory dist
```

## 4. Outer Loop: Automated CI/CD Pipeline (Frontend)

The Outer Loop governs the fully automated, immutable deployment of the verified frontend artifact to the AWS cloud environment via GitHub Actions (`.github/workflows/front-end-cicd.yml`).

- **Zero-Trust Identity Federation (OIDC):** The runner dynamically requests a JSON Web Token (JWT) and submits it to AWS STS. The workflow explicitly sets the `role-session-name` to `${{ github.event.repository.name }}-${{ github.run_id }}` to guarantee non-repudiation in CloudTrail logs.
- **Idempotent Deployment:** Execution relies on `aws s3 sync ./dist s3://${{ secrets.S3_BUCKET_NAME }} --delete`. By targeting strictly the `./dist` folder, we enforce Artifact Hygiene, preventing backend scripts from leaking to the public internet.
- **Zero-Downtime Edge Invalidation:** The pipeline automatically executes `aws cloudfront create-invalidation` to purge global edge caches, ensuring immediate content freshness.

## 5. Backend Resource Provisioning (The ClickOps Foundation)

While the frontend is fully automated, the serverless backend is currently provisioned manually. _Critical SRE Note: Secrets and Identity Providers must be provisioned before the compute layers that require them._

1. **Provision the Data Layer (DynamoDB):** Create a DynamoDB table named `VisitorCount` with a primary partition key `id` (String). Set billing mode to On-Demand to optimize for free-tier usage.
2. **Configure Compute (Lambda):** Create the Counter Lambda (Python) and assign a least-privilege IAM role scoped strictly to `dynamodb:UpdateItem` and `dynamodb:GetItem` for the specific table ARN.
3. **Establish the API Boundary (API Gateway):** Create an HTTP API. Map routes to integrate with their respective Lambda functions. Configure the CORS policy to strictly allow origins from your registered domain (`https://vikram-sre.dev`).

## 6. Disaster Recovery: Ingress & Edge Routing (Layer 7)

**Objective:** To achieve near-zero **MTTR** in the event of accidental Cloudflare zone deletion, registrar compromise, or TLS certificate revocation. This section codifies the exact state required to rebuild the **Zero-Trust** public boundary natively within Cloudflare and AWS ACM.

### 6.1. Registrar & Authoritative DNS Recovery (`vikram-sre.dev`)

If the Cloudflare DNS zone is purged or corrupted, DNS resolution will fail globally. Execute the following to restore authoritative routing and edge security policies:

1. **Recreate DNS Zone:** Add `vikram-sre.dev` back into the Cloudflare dashboard.
2. **Re-establish CNAME Flattening:** - Navigate to **DNS > Records**.
   - Add a `CNAME` record for `@` (Root) pointing to your AWS CloudFront distribution string (e.g., `d111111abcdef8.cloudfront.net`).
   - **Critical SRE Action:** Set Proxy status to **DNS Only (Grey Cloud)**.
3. **Re-establish WWW Routing:**
   - Add a `CNAME` record for `www` pointing to `vikram-sre.dev`.
   - **Critical SRE Action:** Set Proxy status to **DNS Only (Grey Cloud)**.
4. **Hardcode Transit Security:**
   - Navigate to **SSL/TLS > Edge Certificates**.
   - Set **Minimum TLS Version** to **TLS 1.3** to isolate the cryptographic perimeter and block legacy handshake downgrade attacks.

### 6.2. Cryptographic Identity Recovery (ACM TLS)

If the TLS certificate is accidentally revoked or deleted, the native **HSTS** preload on the `.dev` TLD will cause browsers to hard-block your site, causing a total ingress failure.

1. **Request New Certificate:** Navigate to AWS Certificate Manager (ACM) in `us-east-1` (mandatory region for CloudFront edge deployment).
2. **Scope:** Request a public certificate for `vikram-sre.dev` and `*.vikram-sre.dev`.
3. **DNS Validation via Cloudflare:** Extract the provided CNAME name/value pairs from AWS ACM and inject them into your Cloudflare DNS portal.
   - _Recorded Validation State:_ - Type: `CNAME`
     - Name: `_PLACEHOLDER_NAME` (Omit `.vikram-sre.dev` if Cloudflare auto-appends).
     - Target: `_PLACEHOLDER_VALUE.acm-validations.aws`
     - Proxy Status: **DNS Only (Grey Cloud)** (Required for ACM to rapidly poll the validation token).
4. **Re-attach to Edge:** Once the certificate status shifts to _Issued_, edit the CloudFront Distribution's General Settings and select the newly generated custom SSL certificate to restore your **Blast Radius Containment** boundary.
