### System Design Implications (HLD/LLD)

Before executing provisioning steps, it is critical to outline the data flow logic. Traffic flows from the external network via Route 53 to the CloudFront Edge, acting as the public boundary. S3 data remains strictly private. API calls from the client browser traverse through API Gateway—acting as the proxy boundary—to invoke Lambda, which securely interacts with the DynamoDB data layer within an AWS-managed VPC.

### Resource Provisioning Outline

The following outlines the logical sequence required to build this environment:

1. **Provision the Data Layer (DynamoDB):** Create a DynamoDB table named `VisitorCount` with a primary partition key `id` (String).
2. **Configure Compute (Lambda):** Create a Python-based Lambda function, assign the least-privilege IAM execution role, and upload the backend application logic.
3. **Establish the API Boundary (API Gateway):** Create an HTTP API. Map a route to integrate with the Lambda function and configure the CORS policy.
4. **Deploy Frontend Storage (S3):** Create an S3 bucket with public access blocked, and upload the formatted HTML/CSS/JS files.
5. **Configure Global Delivery (CloudFront & Route53):** Deploy a CloudFront distribution pointing to the S3 bucket via Origin Access Control (OAC). Finally, route domain traffic by creating an A-Record in Route 53.

### Conceptual Bridge to Infrastructure as Code (IaC)

While the sequence above details a manual (ClickOps or AWS CLI) deployment approach, this exact state is designed to be translated into declarative configuration tools like Terraform. In a future iteration, `aws_dynamodb_table`, `aws_lambda_function`, `aws_apigatewayv2_api`, and `aws_iam_policy` resources will replace these manual steps, shifting the workflow from imperative commands to idempotent, version-controlled infrastructure code.
