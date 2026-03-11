# ADR 0003: Compute Layer for Backend API

## Context

The application requires a backend compute layer to handle dynamic interactions, specifically incrementing the visitor counter and fetching live credential statuses. We need a solution that balances operational overhead, scalability, and strict cost controls.

## Options Considered

- **Amazon EC2 (Virtual Machines):** Requires provisioning an instance, managing OS patching, configuring VPCs/Subnets, and paying hourly idle costs.
- **Amazon ECS (Containers):** Excellent for microservices, but requires maintaining cluster infrastructure or paying for Fargate idle time.
- **AWS Lambda + API Gateway (Serverless):** Event-driven compute. Scales to zero. No OS management.

## Decision

We will adopt the Serverless model using AWS Lambda triggered by Amazon API Gateway.

## Security, FinOps, and Architecture Critique

- **FinOps (Cost Control):** This event-driven model completely eliminates idle holding costs. It fits securely within the AWS Free Tier, adhering to our strict ₹500/month budget guardrails.
- **Security & IAM:** Lambda allows us to enforce the Principle of Least Privilege at the function level. The execution role will strictly limit access to specific DynamoDB ARNs and SSM Parameter Store keys, preventing horizontal privilege escalation.
- **Network & Throttling:** API Gateway acts as a protective proxy boundary. We can enforce rate limiting and Cross-Origin Resource Sharing (CORS) before the compute layer is ever invoked, mitigating denial-of-wallet attacks.

## Conceptual Bridge to IaC

When transitioning this manual deployment to Terraform, we will utilize `aws_lambda_function` and `aws_apigatewayv2_api` resources. This declarative approach will replace imperative CLI commands, ensuring the compute layer is idempotent and version-controlled.
