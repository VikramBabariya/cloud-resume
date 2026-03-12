### Principle of Least Privilege

To minimize the blast radius of potential security incidents, the AWS Lambda execution role was configured following strict least-privilege principles. The role strictly allows `dynamodb:UpdateItem` and `dynamodb:GetItem` actions, and it is firmly scoped to the specific Amazon Resource Name (ARN) of the Visitor Counter DynamoDB table. The function has no permissions to access other databases, S3 buckets, or external cloud resources.

### Cost Control & Billing Alarms

To maintain strict cost boundaries and detect potential abuse (e.g., recursive loops or layer-7 DDoS attempts against the API), AWS CloudWatch Billing Alarms were implemented. Alerts are configured to notify via SNS if monthly estimated charges exceed initial Free Tier thresholds ($1.00 and $5.00), preventing unexpected financial spikes.

### Additional Security Considerations

- **CORS Restrictions:** API Gateway is configured with strict Cross-Origin Resource Sharing (CORS) rules, ensuring the backend logic can only be invoked by the legitimate `vb-web.in` frontend domain.
