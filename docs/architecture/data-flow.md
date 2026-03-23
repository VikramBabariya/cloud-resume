# Level 1 Data Flow Diagram: Serverless Backend

## Context

While the System Architecture diagram outlines the physical cloud infrastructure, this Data Flow Diagram (DFD) maps the logical lifecycle of payloads traversing the system. It explicitly defines the routing logic, data state transformations, and security boundaries for the dual-path API.

## Diagram

![Level 1 Data Flow Diagram](export/data-flow-level-1.png)
_(Diagram source maintained via Mermaid.js in `/docs/architecture/source/`)_

## Process Analysis

- **Flow A (Visitor Counter):** Demonstrates the asynchronous trigger and atomic `ADD` operation against the NoSQL data store, ensuring concurrency control.
- **Flow B (Credential Validation):** Illustrates the threat model for secrets management. The database (SSM) explicitly returns a KMS-encrypted string, which the Lambda function decrypts in memory before injecting it into the outbound HTTPS header for the third-party API request.
