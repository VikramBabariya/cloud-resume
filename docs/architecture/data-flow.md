# Level 1 Data Flow Diagram: Serverless Backend & Zero-Trust Delivery

## Context

While the System Architecture diagram outlines the physical cloud infrastructure, this Data Flow Diagram (DFD) maps the logical lifecycle of payloads traversing the system. It explicitly defines the routing logic, data state transformations, deployment pipelines, and **Zero-Trust** security boundaries for both client-side requests and internal CI/CD mutations.

## Diagram

![Level 1 Data Flow Diagram](export/data-flow-level-1.png)
_(Diagram source maintained via Diagrams as Code (Mermaid.js) in `/docs/architecture/source/`)_

## Process Analysis

- **Phase 1: Public Ingress & Static Delivery:** Details the **HSTS**-enforced routing of external client traffic through the `vikram-sre.dev` perimeter to the CloudFront CDN, serving static artifacts from the securely isolated S3 datastore.
- **Phase 2: (Visitor Counter):** Demonstrates the asynchronous API trigger, proxy routing, and the atomic `ADD` operation against the DynamoDB NoSQL data store, ensuring strict concurrency control and data integrity.
- **Phase 3: (Zero-Trust Delivery Pipeline):** Maps the **SRE Maturity Level 3** deployment lifecycle. It visualizes the ingestion of the YAML Source of Truth, the assumption of ephemeral credentials via **OIDC Federation**, the **Idempotent** state synchronization (`--delete`), and the final edge cache invalidation to achieve **Zero-Downtime** releases.
- **Phase 4: (IaC Delivery Pipeline):** Maps the Terraform-driven infrastructure mutation lifecycle. A `terraform/**` change triggers the `terraform-cicd.yml` pipeline, which authenticates via the same OIDC federation as the frontend pipeline (isolated `role-session-name`). The pipeline runs shift-left gates (`fmt → validate → checkov → plan`) before applying. All state transitions are written to and locked via the dedicated S3 state backend (`D3`) and DynamoDB lock table (`D4`). On apply, infrastructure resources — including `D1` (S3 origin bucket) — are provisioned or mutated, making this pipeline the authoritative source of infrastructure change.
