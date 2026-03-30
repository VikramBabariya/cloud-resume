# ADR 0005: Resume as Code (Content Decoupling and Templating)

## Status

Accepted

## Context

The initial frontend architecture relied on manually editing static HTML files to update professional experience, certifications, and skills. As the system matures, this manual approach introduces significant operational toil. Mixing the data layer (career history) with the presentation layer (HTML/CSS) increases the risk of UI regressions, accessibility (a11y) violations, and formatting inconsistencies during routine content updates.

## Options Considered

- **Manual HTML Editing:** Low initial setup, but high ongoing maintenance. Violates the DRY (Don't Repeat Yourself) principle and makes Git diffs difficult to parse.
- **Headless CMS (e.g., Contentful, Sanity):** Excellent decoupling, but introduces unnecessary API latency, external dependencies, and over-engineering for a single-page static portfolio.
- **"Resume as Code" (Structured Data + Build Engine):** Storing content in a flat, version-controlled data file and generating the static HTML via a build script in the CI/CD pipeline.

## Decision

We will adopt the **"Resume as Code"** methodology. All professional content will be strictly decoupled from the HTML shell and stored in a version-controlled `resume.yaml` file. A build script or Static Site Generator (SSG) will compile this data into the final static HTML artifact during the deployment phase.

## Architecture and DevOps Critique

- **Separation of Concerns:** By isolating the data layer, frontend design updates (CSS/HTML changes) can be executed entirely independently of content updates.
- **Developer Experience (DX):** YAML was explicitly chosen over JSON for the data store. YAML natively supports multi-line strings (essential for job descriptions) and comments, making human-authored text significantly easier to write and review during Pull Requests.
- **GitOps Alignment:** This forces the implementation of a true CI/CD build phase. The GitHub Actions workflow will no longer just sync files; it will compile the software, mirroring enterprise deployment patterns.
- **Immutability:** The deployed `index.html` in the S3 bucket is now treated as an ephemeral, compiled artifact. The true state of the application lives exclusively in the YAML source code.

## Consequences

- **Schema Enforcement:** We must define and adhere to a strict data schema to ensure the build engine parses the YAML correctly without failing the pipeline.
- **Pipeline Expansion:** The GitHub Actions workflow must be upgraded to include dependency installation and a build step before executing the S3 sync and CloudFront invalidation.
- **Local Development:** The operational runbook must be updated. Local development now requires running a build script to preview content changes, slightly increasing the initial local setup friction.
