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

> ⚠️ **DEPRECATED — Superseded by Terraform IaC**
>
> This section describes the original manual ("ClickOps") provisioning steps. These steps are **no longer the authoritative procedure**. All backend resources (DynamoDB, Lambda, API Gateway, IAM roles, OIDC provider, CloudFront, ACM, S3 origin, Cloudflare DNS, and the FinOps budget alarm) are now fully managed by Terraform under `terraform/`. For the current bootstrap and operational procedures, see **Section 6: IaC Bootstrap Prerequisites** and **Section 8: IaC Day-2 Operations**.
>
> The steps below are retained as a **historical reference only** to document the pre-Terraform state of the platform. Do not follow them for new deployments.

### 5.1. Historical ClickOps Steps (Deprecated — Do Not Follow)

1. **Provision the Data Layer (DynamoDB):** Create a DynamoDB table named `VisitorCount` with a primary partition key `id` (String). Set billing mode to On-Demand to optimize for free-tier usage.
2. **Configure Compute (Lambda):** Create the Counter Lambda (Python) and assign a least-privilege IAM role scoped strictly to `dynamodb:UpdateItem` and `dynamodb:GetItem` for the specific table ARN.
3. **Establish the API Boundary (API Gateway):** Create an HTTP API. Map routes to integrate with their respective Lambda functions. Configure the CORS policy to strictly allow origins from your registered domain (`https://vikram-sre.dev`).

## 6. IaC Bootstrap Prerequisites (One-Time Manual Steps)

> **Context:** Terraform cannot manage its own state backend — the S3 bucket, DynamoDB lock table, and KMS key must exist before `terraform init` can reference them. These steps are performed **once per environment** by a platform engineer with console access. All subsequent infrastructure changes are automated through the CI/CD pipeline (`terraform-cicd.yml`).

### Step 1 — Create the KMS Key for State Encryption

In the **AWS Console → KMS → Customer managed keys** (`ap-south-1` region):

1. Create a **Symmetric** key with key usage `Encrypt and decrypt`.
2. Set the alias to `alias/terraform-state`.
3. Keep the default key policy (your AWS account as key administrator).

> **Why manual?** The KMS key must exist before the S3 backend bucket can be configured with SSE-KMS. Terraform cannot create the key before it has a place to store state — this is an intentional bootstrap constraint.

### Step 2 — Create the S3 State Bucket

In the **AWS Console → S3** (`ap-south-1` region), create a new bucket:

- **Bucket name:** `zero-trust-rac-tfstate`
- **Region:** `ap-south-1`
- **Block all public access:** ✅ enabled (all four settings)
- **Versioning:** ✅ `Enabled`
- **Default encryption:** SSE-KMS using `alias/terraform-state`

> Versioning is required so that a corrupted or accidentally overwritten state file can be rolled back to a known-good version.

### Step 3 — Create the DynamoDB State Lock Table

In the **AWS Console → DynamoDB → Tables** (`ap-south-1` region), create a new table:

- **Table name:** `zero-trust-rac-tfstate-lock`
- **Partition key:** `LockID` (type: **String**)
- **Table class:** DynamoDB Standard
- **Billing mode:** On-demand (PAY_PER_REQUEST)

> The `LockID` partition key is the exact string Terraform's S3 backend writes to prevent concurrent `terraform apply` runs from corrupting the state file.

### Step 4 — Run `terraform init`

With the state backend resources in place, initialise Terraform from the `terraform/` directory:

```bash
cd terraform/
terraform init
```

Terraform will connect to the S3 backend, verify the DynamoDB lock table, and download all provider plugins. A successful init confirms the bootstrap is complete.

### Step 5 — Run `terraform apply` and Confirm SNS Subscription

```bash
terraform plan   # Review the execution plan first
terraform apply
```

After `apply` completes, AWS will send a **subscription confirmation email** to the address supplied as `notification_email`. You must click the confirmation link in that email to activate cost alert notifications. This is a one-time manual step — SNS email subscriptions cannot be auto-confirmed via API.

> Until the subscription is confirmed, the AWS Budgets alarm is provisioned but notifications will not be delivered.

### State Lock Recovery

If a `terraform apply` fails mid-execution (e.g., network interruption, runner timeout), the DynamoDB lock entry may be left orphaned, blocking all subsequent runs with:

```
Error: Error acquiring the state lock
```

To force-unlock, retrieve the `LOCK_ID` from the error output and run:

```bash
terraform force-unlock <LOCK_ID>
```

> ⚠️ **Always check AWS CloudTrail** for any in-progress or failed API calls before force-unlocking. Force-unlocking while an apply is still running (e.g., on a slow Lambda deploy) can corrupt the state file. Only use this when you are certain no concurrent operation is active.

---

## 7. Disaster Recovery: Ingress & Edge Routing (Layer 7)

**Objective:** To achieve near-zero **MTTR** in the event of accidental Cloudflare zone deletion, registrar compromise, or TLS certificate revocation. This section codifies the exact state required to rebuild the **Zero-Trust** public boundary natively within Cloudflare and AWS ACM.

### 7.1. Registrar & Authoritative DNS Recovery (`vikram-sre.dev`)

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

### 7.2. Cryptographic Identity Recovery (ACM TLS)

If the TLS certificate is accidentally revoked or deleted, the native **HSTS** preload on the `.dev` TLD will cause browsers to hard-block your site, causing a total ingress failure.

1. **Request New Certificate:** Navigate to AWS Certificate Manager (ACM) in `us-east-1` (mandatory region for CloudFront edge deployment).
2. **Scope:** Request a public certificate for `vikram-sre.dev` and `*.vikram-sre.dev`.
3. **DNS Validation via Cloudflare:** Extract the provided CNAME name/value pairs from AWS ACM and inject them into your Cloudflare DNS portal.
   - _Recorded Validation State:_ - Type: `CNAME`
     - Name: `_PLACEHOLDER_NAME` (Omit `.vikram-sre.dev` if Cloudflare auto-appends).
     - Target: `_PLACEHOLDER_VALUE.acm-validations.aws`
     - Proxy Status: **DNS Only (Grey Cloud)** (Required for ACM to rapidly poll the validation token).
4. **Re-attach to Edge:** Once the certificate status shifts to _Issued_, edit the CloudFront Distribution's General Settings and select the newly generated custom SSL certificate to restore your **Blast Radius Containment** boundary.

---

## 8. IaC Day-2 Operations

This section covers routine operational tasks for platform engineers working with the Terraform codebase after the initial bootstrap (Section 6) is complete.

### 8.1. Running `terraform plan` Locally

A local plan lets you preview infrastructure changes before pushing to a PR. You need AWS credentials and the required Terraform variables available in your shell.

```bash
cd terraform/

# Export sensitive variables — never write these to a .tfvars file
export TF_VAR_cloudflare_api_token="<your-cloudflare-api-token>"
export TF_VAR_aws_account_id="<your-aws-account-id>"
export TF_VAR_notification_email="<your-notification-email>"

# Run the plan
terraform plan
```

The plan output shows exactly which resources will be created, modified, or destroyed. Review the diff carefully before pushing — the CI pipeline will post the same plan output as a PR comment for reviewer visibility.

> Sensitive variable values are redacted from all plan and apply output (`sensitive = true` is set on each variable declaration). You will see `(sensitive value)` in the output rather than the actual token or email.

### 8.2. Adding a New Environment

The Terraform root supports multiple environments via [workspaces](https://developer.hashicorp.com/terraform/language/state/workspaces). Each workspace gets its own isolated state file in the S3 backend.

To add a new environment (e.g., `staging`):

1. **Create a new workspace:**

   ```bash
   cd terraform/
   terraform workspace new staging
   ```

2. **Create a corresponding `terraform.tfvars` file for the new environment** (never commit this file — it is covered by `.gitignore`):

   ```bash
   cp terraform.tfvars.example terraform.staging.tfvars
   # Edit terraform.staging.tfvars with staging-specific values
   ```

3. **Plan and apply with the environment-specific vars:**

   ```bash
   terraform plan -var-file="terraform.staging.tfvars"
   terraform apply -var-file="terraform.staging.tfvars"
   ```

> **Rule:** No file under `modules/` should be created, modified, or deleted when adding a new environment. Environment differences are expressed entirely through workspace selection and `terraform.tfvars` values. If a new environment requires a structural module change, open a PR and document it in an ADR first.

### 8.3. Reading Checkov Suppression Comments

The Terraform codebase uses inline checkov suppression comments for findings that are intentional architectural decisions — not oversights. Every suppression follows this exact format:

```hcl
# checkov:skip=CKV_ID:Human-readable reason referencing the justifying ADR or FinOps constraint
```

**Example:**

```hcl
resource "aws_cloudfront_distribution" "this" {
  # checkov:skip=CKV_AWS_86:CloudFront access logging disabled — FinOps hard cap ($6/mo, ADR 0002) makes per-request log storage cost-prohibitive
  # checkov:skip=CKV_AWS_68:WAF not attached — outside FinOps hard cap; network boundary enforced at CloudFront OAC level (ADR 0002)
  ...
}
```

When you encounter a `checkov:skip` comment:

- **Do not remove it** without understanding the referenced constraint. Removing a suppression will cause the CI pipeline to fail on the next PR if the underlying finding is still present.
- **If the constraint no longer applies** (e.g., the FinOps cap is raised), remove the suppression, re-run checkov locally (`checkov -d . --framework terraform --compact`), and confirm the finding is now resolved rather than re-suppressed.
- **If you are adding a new suppression**, you must include a reason that references the specific ADR, incident, or FinOps constraint that justifies the waiver. Blanket suppressions without a documented reason will be rejected in code review.
