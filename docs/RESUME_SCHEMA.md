# Architecture Decision & Data Contract: Resume Schema

## 1. System Design Implications (HLD/LLD)

In the "Resume as Code" architecture, the presentation layer (HTML/CSS) is strictly decoupled from the data layer. This document serves as the Low-Level Design (LLD) contract for the data layer.

- **The Source of Truth:** All professional history, metrics, and skills are maintained in a single, version-controlled file located at `data/resume.yaml`.
- **The Downstream Dependency:** The Python/Jinja2 build engine relies entirely on the structural predictability of this file. If the schema is violated, the pipeline will fail, or worse, deploy a malformed UI to the production S3 bucket.

## 2. The Data Standard (JSON Resume)

To ensure tool agnosticism and prevent schema-design paralysis, this project adopts the open-source **[JSON Resume Standard](https://jsonresume.org/schema/)**.

While the standard is natively JSON, we utilize **YAML** for human-readability and multi-line string support. The data structure maps exactly 1:1 with the JSON Resume requirements.

### Core Entity Structure

The `resume.yaml` file must contain the following root-level arrays and dictionaries:

- `basics`: Core identity, contact info, and professional summary.
- `work`: Professional experience (Must be chronological, newest first).
- `education`: Academic history.
- `skills`: Grouped technical competencies (e.g., Cloud & Serverless, DevOps).
- `projects`: Key architectural builds (e.g., Cloud Resume, Microservices).
- `certificates`: Verifiable industry certifications (e.g., AWS CCP).

## 3. SRE Reliability Gate: Two-Stage Validation

To prevent "garbage in, garbage out" deployments, the CI/CD pipeline enforces a strict two-stage validation gate before the build engine is allowed to compile the code.

### Stage 1: Syntax Validation (yamllint)

- **Purpose:** Ensures the file mechanics are flawless.
- **Checks:** Enforces YAML 1.2 specifications, 2-space indentation, trailing newlines, and prevents duplicate keys.
- **Failure State:** Catches structural indentation errors that would cause the Python `pyyaml` library to crash.

### Stage 2: Semantic Validation (ajv-cli)

- **Purpose:** Ensures the business logic matches the data contract.
- **Checks:** Validates the parsed YAML against the official `schema.json` from JSON Resume.
- **Failure State:** Catches missing mandatory fields (e.g., a missing `startDate`), invalid email formats, or incorrect data types (e.g., passing an integer when a string is expected).

## 4. Security & Threat Modeling Considerations

Treating content as code introduces injection vulnerabilities.

- **Input Sanitization:** The validation gates ensure no executable scripts (e.g., `<script>` tags injected into a YAML string) bypass the schema definitions.
- **Immutability:** The production S3 bucket only ever receives the compiled HTML artifact. The raw YAML and validation schemas are securely isolated within the GitHub repository and never exposed to the public web boundary.
