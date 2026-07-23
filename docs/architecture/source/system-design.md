# System Architecture: Zero-Trust RaC Platform

This document serves as the Single Source of Truth (SSoT) for the network topology, data flow, and security boundaries of the Zero-Trust Resume-as-Code (RaC) Platform.

### Edge-Network & Public Ingress Boundary

**Strategic Ingress Definition:** The public entry point for this platform is strictly governed by the `vikram-sre.dev` namespace. This boundary acts as the primary **Shift-Left Quality Gate** for human evaluation, optimizing **MTTE**. To enforce strict **FinOps** cost boundaries and reduce architectural complexity, authoritative name resolution is entirely consolidated within Cloudflare's global Anycast network, completely bypassing AWS Route 53.

> **Architectural Decision Record:** For the definitive technical justification regarding this single-provider consolidation, the choice of a **DNS Only (Grey Cloud)** configuration, and the native **HSTS** edge mechanics, refer to:
> [ADR 0008: Strategic Domain Name Ingress and Registrar Procurement Selection](../../adr/0008-domain-and-registrar-selection.md)

---

### Architecture Topology

```mermaid
graph TD
%% Styles & Color Taxonomy
classDef client fill:#5A6B86,stroke:#232F3E,stroke-width:2px,color:#FFF;
classDef edge fill:#242F3E,stroke:#3F8624,stroke-width:2px,color:#FFF;
classDef compute fill:#FF9900,stroke:#232F3E,stroke-width:2px,color:#FFF;
classDef db fill:#3B48CC,stroke:#232F3E,stroke-width:2px,color:#FFF;
classDef sec fill:#DD344C,stroke:#232F3E,stroke-width:2px,color:#FFF;
classDef ext fill:#8C4FFF,stroke:#232F3E,stroke-width:2px,color:#FFF;
classDef obs fill:#E7157B,stroke:#232F3E,stroke-width:2px,color:#FFF;
classDef cicd fill:#2088FF,stroke:#232F3E,stroke-width:2px,color:#FFF;
classDef idp fill:#24292E,stroke:#FFF,stroke-width:2px,color:#FFF;

    %% --- Architectural Tiers ---

    subgraph Tier0_Ingress ["Consolidated Cloudflare Ingress Boundary"]
        CF_Edge["Cloudflare Registrar & DNS <br> vikram-sre.dev (Grey Cloud)"]:::ext
    end

    subgraph Tier1_Client ["Client Zone"]
        User((User/Browser)):::client
    end

    subgraph Tier2_Delivery ["AWS Edge & Delivery Layer"]
        CF[CloudFront <br> Global CDN]:::edge
        S3[S3 Bucket <br> Static Assets]:::db
        ACM[ACM <br> TLS Certificate]:::sec
    end

    subgraph Tier3_Backend ["Serverless Compute Layer"]
        APIG[API Gateway <br> REST API Proxy]:::compute
        LambdaCount[Lambda Function <br> Visitor Counter]:::compute
    end

    subgraph Tier4_Data ["Data Layer"]
        DDB[(DynamoDB <br> NoSQL Table)]:::db
    end

    subgraph Tier_OIDC ["Ephemeral Credential Flow (Zero-Trust)"]
        GHRunner[GitHub Actions <br> CI/CD Runner]:::cicd
        GHIdP[GitHub OIDC IdP <br> Identity Provider]:::idp
        STS[AWS STS <br> Security Token Service]:::sec
        IAM[IAM Trust Policy <br> Condition Gatekeeper]:::sec

        subgraph TF_IaC ["Terraform IaC Pipeline"]
            TF_Pipeline["terraform-cicd.yml<br>fmt → validate → checkov → plan → apply"]:::cicd
            TF_State["S3 State Backend<br>(SSE-KMS, versioning)"]:::db
            TF_Lock["DynamoDB Lock<br>(LockID)"]:::db
        end
    end

    subgraph Layer_Observability ["Observability & Telemetry"]
        CW[CloudWatch <br> Logs & Alarms]:::obs
        XRay[X-Ray <br> Distributed Tracing]:::obs
    end

    %% --- Data Flow & Networking ---

    %% Public Internet & Ingress
    User -- "1. Request / DNS Query" --> CF_Edge
    CF_Edge -- "2. CNAME Flattening (A Record Equivalent)" --> CF
    CF -. "3. Negotiates TLS & HSTS" .- ACM
    CF -- "4. Origin Access Control (OAC)" --> S3

    %% Frontend API Calls
    S3 -- JS Async Fetch --> APIG

    %% Microservice A: Counter
    APIG -- Route: /counter --> LambdaCount
    LambdaCount -- dynamodb:UpdateItem --> DDB

    %% Telemetry Mapping
    APIG -. Request Tracing .-> XRay
    LambdaCount -. Execution Logs .-> CW
    LambdaCount -. Traces .-> XRay

    %% --- Zero-Trust OIDC Federation & Deployment ---
    GHRunner -- 1. Requests JWT --> GHIdP
    GHIdP -- 2. Issues Signed JWT --> GHRunner
    GHRunner -- 3. Submits JWT <br> (AssumeRoleWithWebIdentity) --> STS
    STS -. "4. Validates Token Claims vs." .- IAM
    STS -- 5. Returns Ephemeral Session Token --> GHRunner

    GHRunner -- "6. Idempotent Deployment <br> (aws s3 sync --delete)" --> S3
    GHRunner -- 7. Cache Invalidation <br> (create-invalidation) --> CF

    %% --- Terraform IaC Pipeline Flows ---
    TF_Pipeline -->|"OIDC AssumeRoleWithWebIdentity"| IAM
    TF_Pipeline -->|"terraform state r/w"| TF_State
    TF_Pipeline -->|"state lock/unlock"| TF_Lock
    TF_Pipeline -->|"provisions all AWS resources"| CF
    TF_Pipeline -->|"provisions all AWS resources"| S3
```

> **Pipeline separation note:** `GHRunner` (frontend pipeline, `front-end-cicd.yml`) and `TF_Pipeline` (IaC pipeline, `terraform-cicd.yml`) are separate GitHub Actions workflow files. Both authenticate via the same OIDC trust relationship with AWS, but use different `role-session-name` values (`github-actions-<run_id>` vs `terraform-<run_id>`) to distinguish sessions in CloudTrail and IAM condition evaluation.
