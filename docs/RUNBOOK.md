# Cloud Resume Project: Operational Runbook

## 1. System Design Implications (HLD/LLD) & Networking Principles

Before executing any provisioning steps, you must understand the data flow, network boundaries, and underlying networking principles of this dual-path architecture:

- **Public Boundary (RFC 1918 & NAT Consideration):** Traffic flows from the public internet via Route 53 to the CloudFront Edge network. The origin S3 bucket remains strictly private within the AWS network, accessible only via Origin Access Control (OAC). No public IP addresses are assigned to internal resources.
- **API & Proxy Boundary:** API Gateway acts as the secure entry point, proxying HTTPS requests from the client browser to the appropriate backend microservice.
- **Flow A (Visitor Counter):** API Gateway invokes the Counter Lambda, which executes an atomic `ADD` operation against the DynamoDB data layer.
- **Flow B (Dynamic Credentialing):** API Gateway invokes the Validator Lambda. This function securely retrieves an encrypted external API key from AWS SSM Parameter Store, decrypts it in memory, and makes an outbound HTTPS call to cryptographically verify the AWS certification badge.

## 2. FinOps Pre-Flight Check

**WARNING:** Do not proceed with AWS provisioning until you have verified your AWS Free Tier limits and established cost governance.

- Ensure an AWS Budgets hard alarm is set to **$6.00 USD (approx. ₹500 INR)**.
- Ensure billing alerts are configured to notify your administrative email at 50% and 100% of the forecasted budget.

## 3. Local Development & Validation (The Inner Loop)

This project utilizes a "Resume as Code" methodology. You must validate and compile the YAML data locally before committing code to trigger the GitHub Actions pipeline.

### Prerequisites

- Node.js & npm (for Prettier, Husky, and JSON Schema validation)
- Python 3.x (for the Jinja2 build engine and YAML linting)

### Step 3.1: Install Validation Tooling

```bash
# Install the JSON Schema validator
npm install -g ajv-cli

# Install the Python YAML linter and build dependencies
pip install yamllint jinja2 pyyaml
```

### Step 3.2: SRE Two-Stage Data Validation

Execute these commands to test the data contract locally. If either of these fails, do not commit.

```bash
# Stage 1: Syntax Gate (Verifies YAML mechanics)
yamllint data/resume.yaml

# Stage 2: Semantic Gate (Verifies business logic against the JSON Resume Standard)
ajv validate -s docs/schema.json -d data/resume.yaml
```

### Step 3.3: Compile the Frontend

Once validation passes, execute the build engine to merge the data with the Jinja2 template.

```bash
python build.py
```

_Note: The generated static artifacts will be output to the ./dist directory._

## 4. Resource Provisioning (The Outer Loop)

The following outlines the logical, dependency-driven sequence required to build the cloud environment. Critical SRE Note: Secrets must be provisioned before the compute layer that requires them.

**1. Provision the Data Layer (DynamoDB):** Create a DynamoDB table named `VisitorCount` with a primary partition key `id` (String). Set billing mode to On-Demand to optimize for free-tier usage.

**2. Provision Secrets Management (SSM):** Create an AWS Systems Manager (SSM) Parameter of type `SecureString` to hold the external certification API key. Ensure it is encrypted using the default AWS KMS key.

**3. Configure Compute (Lambda):**

- Create the **Counter Lambda** (Python) and assign a least-privilege IAM role scoped strictly to `dynamodb:UpdateItem` and `dynamodb:GetItem` for the specific table ARN.

- Create the **Validator Lambda** (Python) and assign a least-privilege IAM role scoped strictly to `ssm:GetParameter` for the specific SSM parameter ARN. Upload the backend application logic for both functions.

**4. Establish the API Boundary (API Gateway):** Create an HTTP API. Map two distinct routes (e.g., `/counter` and `/verify`) to integrate with their respective Lambda functions. Configure the CORS policy to strictly allow origins from your registered domain.

**5. Build and Deploy Frontend Storage (S3):**
_Critical SRE Note: Do not sync the root repository to S3._ You must first execute the local build script to compile the HTML artifact. Create an S3 bucket with public access blocked, and upload only the compiled output directory (`./dist`).

**6. Configure Global Delivery (CloudFront & Route 53):** Deploy a CloudFront distribution pointing to the S3 bucket via Origin Access Control (OAC). Finally, route domain traffic by creating an A-Record in Route 53 pointing to the CloudFront distribution.

## 5. Conceptual Bridge to Infrastructure as Code (IaC)

While the sequence above details a manual deployment approach, this state is designed to be translated into declarative configuration tools like Terraform. In our upcoming IaC sprint, the imperative steps will be replaced by the following resources: `aws_dynamodb_table`, `aws_ssm_parameter`, `aws_iam_role`, `aws_iam_role_policy`, `aws_lambda_function`, and `aws_apigatewayv2_api`.
