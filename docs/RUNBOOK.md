### System Design Implications (HLD/LLD)

Before executing provisioning steps, it is critical to outline the data flow logic for the dual-path backend architecture.

- **Public Boundary:** Traffic flows from the external network via Route 53 to the CloudFront Edge. S3 data remains strictly private.
- **API & Proxy Boundary:** API calls from the client browser traverse through API Gateway, which proxies requests to the appropriate backend service.
- **Flow A (Visitor Counter):** API Gateway invokes the Counter Lambda, which securely interacts with the DynamoDB data layer within an AWS-managed VPC.
- **Flow B (Dynamic Credentialing):** API Gateway invokes the Validator Lambda. This function securely retrieves an encrypted external API key from AWS SSM Parameter Store, decrypts it in memory, and makes an outbound HTTPS call to the third-party certification provider to cryptographically verify the badge.

### Resource Provisioning Outline

The following outlines the logical, dependency-driven sequence required to build this environment. _Critical SRE Note: Secrets must be provisioned before the compute layer that requires them._

1. **Provision the Data Layer (DynamoDB):** Create a DynamoDB table named `VisitorCount` with a primary partition key `id` (String).
2. **Provision Secrets Management (SSM):** Create an AWS Systems Manager (SSM) Parameter of type `SecureString` to hold the external certification API key. Ensure it is encrypted using the default AWS KMS key.
3. **Configure Compute (Lambda):** \* Create the **Counter Lambda** (Python) and assign a least-privilege IAM role scoped strictly to `dynamodb:UpdateItem` and `dynamodb:GetItem` for the specific table ARN.
   - Create the **Validator Lambda** (Python) and assign a least-privilege IAM role scoped strictly to `ssm:GetParameter` for the specific SSM parameter ARN. Upload the backend application logic for both functions.
4. **Establish the API Boundary (API Gateway):** Create an HTTP API. Map two distinct routes (e.g., `/counter` and `/verify`) to integrate with their respective Lambda functions. Configure the CORS policy to strictly allow origins from `vb-web.in`.
5. **Deploy Frontend Storage (S3):** Create an S3 bucket with public access blocked, and upload the formatted HTML/CSS/JS files.
6. **Configure Global Delivery (CloudFront & Route 53):** Deploy a CloudFront distribution pointing to the S3 bucket via Origin Access Control (OAC). Finally, route domain traffic by creating an A-Record in Route 53 pointing to the CloudFront distribution.

### Conceptual Bridge to Infrastructure as Code (IaC)

While the sequence above details a manual (ClickOps or AWS CLI) deployment approach, this exact state is designed to be translated into declarative configuration tools like Terraform.

In our upcoming IaC sprint, the imperative steps will be replaced by the following resources: `aws_dynamodb_table`, `aws_ssm_parameter`, `aws_iam_role`, `aws_iam_role_policy`, `aws_lambda_function`, and `aws_apigatewayv2_api`. This transition will shift the workflow from manual console clicks to idempotent, version-controlled infrastructure code.
