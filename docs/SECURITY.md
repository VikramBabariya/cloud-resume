### Principle of Least Privilege

To minimize the blast radius of potential security incidents, all AWS Lambda execution roles are configured following strict least-privilege principles, with distinct roles for each microservice:

- **Visitor Counter Lambda:** The execution role strictly allows `dynamodb:UpdateItem` and `dynamodb:GetItem` actions, and is firmly scoped to the specific Amazon Resource Name (ARN) of the Visitor Counter DynamoDB table. It has zero access to other databases or parameter stores.
- **Credential Validator Lambda:** This function has no access to DynamoDB. Its execution role is strictly scoped to allow `ssm:GetParameter` solely for the exact ARN of the external API key stored in AWS Systems Manager. General `ssm:*` wildcard permissions are explicitly denied.

### Cost Control & Billing Alarms

To maintain strict cost boundaries, detect potential abuse (e.g., recursive loops or layer-7 DDoS attempts against the API), and engineer for FinOps, the following cloud governance policies are enforced:

- **Proactive Alarms:** AWS CloudWatch Billing Alarms are tied to a strict $6.00 monthly budget. Notifications are dispatched to the administrative email when actual costs exceed 35% of the budget, or when forecasted costs reach 100%, preventing unexpected financial spikes.
- **Architectural Cost Avoidance:** To prevent recurring monthly charges while maintaining zero-trust credential storage, the external API key is stored in the standard-tier AWS Systems Manager (SSM) Parameter Store (free) rather than AWS Secrets Manager ($0.40/month).

### Additional Security Considerations

- **Data at Rest:** All sensitive configuration data, including the third-party certification API key, is stored as a `SecureString` in AWS SSM Parameter Store and encrypted at rest using an AWS Key Management Service (KMS) managed key. No plaintext secrets exist in environment variables or application code.
- **Data in Transit:** Traffic between the user's browser and the CloudFront Edge is enforced over HTTPS via an AWS Certificate Manager (ACM) SSL/TLS certificate. Furthermore, all outbound verification calls originating from the Lambda backend to the external credential provider are strictly routed over TLS/HTTPS.
- **CORS Restrictions:** API Gateway is configured with strict Cross-Origin Resource Sharing (CORS) rules. The backend logic rejects unauthorized invocations, ensuring the API can only be successfully called by the legitimate `vb-web.in` frontend domain.
