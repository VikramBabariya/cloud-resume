### Data Store: DynamoDB vs. Relational Database (RDS)

For the visitor counter backend, a NoSQL key-value store was chosen over a traditional relational database to optimize for both cost control and scalability.

| Feature                  | AWS DynamoDB (Chosen)                                                        | Amazon RDS (Alternative)                                                        |
| :----------------------- | :--------------------------------------------------------------------------- | :------------------------------------------------------------------------------ |
| **Data Structure**       | Simple Key-Value pairs (perfect for a single integer counter).               | Complex relational tables (overkill for single-state tracking).                 |
| **Cost Model**           | Pay-per-use. Fits easily within the AWS Free Tier, minimizing holding costs. | Continuous hourly billing regardless of traffic.                                |
| **Performance**          | Single-digit millisecond latency with zero cold-start connection overhead.   | Connection pooling required; higher latency for initial serverless connections. |
| **Operational Overhead** | Fully managed, auto-scaling serverless service.                              | Requires VPC configuration, subnet groups, and manual scaling policies.         |
