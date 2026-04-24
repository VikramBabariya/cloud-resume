# Cloud Resume Project: Operational Runbook

## 1. System Design Implications (HLD/LLD) & Networking Principles

Before executing any provisioning steps, you must understand the data flow, network boundaries, and underlying principles of this architecture:

- **Public Boundary (RFC 1918 & NAT Consideration):** Traffic flows from the public internet via Route 53 to the CloudFront Edge network. The origin S3 bucket remains strictly private within the AWS network, accessible only via Origin Access Control (OAC). No public IP addresses are assigned to internal resources.
- **API & Proxy Boundary:** API Gateway acts as the secure entry point, proxying HTTPS requests from the client browser to the appropriate backend microservice.
- **Flow A (Visitor Counter):** API Gateway invokes the Counter Lambda, which executes an atomic `ADD` operation against the DynamoDB data layer.
- **Flow B (Dynamic Credentialing):** API Gateway invokes the Validator Lambda. This function securely retrieves an encrypted external API key from AWS SSM Parameter Store, decrypts it in memory, and makes an outbound HTTPS call to cryptographically verify the AWS certification badge.
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

# 3. Install Node.js Validation Tooling
npm install
```

### Step 3.2: SRE Quality Gates (Shift-Left Testing)

Execute the local validation wrapper to test the data contract. If this fails, investigate the SRE error trace and do not commit.

```Bash
# Executes yamllint (structural syntax) and ajv-cli (semantic schema validation)
npm run validate
```

### Step 3.3: Compile the Frontend & Verify Locally

Execute the Python compiler to merge the validated data with the Jinja2 template and inject Critical Path CSS.

```Bash
# Generate the dist/index.html artifact
python build.py

# Simulate the Edge Network locally (Bypasses local CORS restrictions)
python3 -m http.server 8000 --directory dist
```

## 4. Resource Provisioning (The Outer Loop)

The following outlines the logical sequence required to build the cloud environment. _Critical SRE Note: Secrets and Identity Providers must be provisioned before the compute layers that require them._

1. Provision the Data Layer (DynamoDB): Create a DynamoDB table named VisitorCount with a primary partition key id (String). Set billing mode to On-Demand to optimize for free-tier usage.

2. Provision Secrets Management (SSM): Create an AWS Systems Manager (SSM) Parameter of type SecureString to hold the external certification API key. Ensure it is encrypted using the default AWS KMS key.

3. Configure Compute (Lambda):

- Create the Counter Lambda (Python) and assign a least-privilege IAM role scoped strictly to dynamodb:UpdateItem and dynamodb:GetItem for the specific table ARN.
- Create the Validator Lambda (Python) and assign a least-privilege IAM role scoped strictly to ssm:GetParameter for the specific SSM parameter ARN.

4. Establish the API Boundary (API Gateway): Create an HTTP API. Map routes to integrate with their respective Lambda functions. Configure the CORS policy to strictly allow origins from your registered domain.

5. Provision Zero-Trust Identity Federation (OIDC): Create an AWS IAM OpenID Connect provider for GitHub (token.actions.githubusercontent.com). Create an IAM Role trusting this provider, scoped exclusively to the main branch of the GitHub repository. Attach inline policies strictly permitting s3:PutObject, s3:DeleteObject, and cloudfront:CreateInvalidation.

6. Build and Deploy Frontend Storage (S3): Critical SRE Note: The S3 sync command must target strictly the ./dist directory using the --delete flag. Create an S3 bucket with public access blocked.

7. Configure Global Delivery (CloudFront & Route 53): Deploy a CloudFront distribution pointing to the S3 bucket via Origin Access Control (OAC). Route domain traffic by creating an A-Record in Route 53.

## 5. Conceptual Bridge to Infrastructure as Code (IaC)

While the sequence above details a manual deployment approach, this state is designed to be translated into declarative configuration tools like Terraform. In our upcoming IaC sprint, these imperative steps will be replaced by the following resources:

- aws_dynamodb_table

- aws_ssm_parameter

- aws_iam_openid_connect_provider
- aws_iam_role & aws_iam_role_policy
- aws_lambda_function
- aws_apigatewayv2_api
- aws_s3_bucket
- aws_cloudfront_distribution
