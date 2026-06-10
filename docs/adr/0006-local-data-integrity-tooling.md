# ADR 0006: Local Data Integrity Tooling

## Status

Accepted

## Context

The Zero-Trust RaC Platform operates on a "Resume as Code" architecture, utilizing `data/resume.yaml` as the single source of truth. The downstream Python build engine (`build.py`) relies heavily on this file adhering to the JSON Resume schema.

Currently, validation only occurs at the build script level. If a developer introduces a syntax error (e.g., malformed YAML indentation) or a semantic error (e.g., missing a required `startDate` field), the failure is caught late in the pipeline, consuming unnecessary CI/CD compute minutes and delaying the feedback loop.

To uphold Site Reliability Engineering (SRE) standards and "Shift-Left" testing principles, we require a robust, local validation gate that developers must pass _before_ committing code.

## Decision

We will implement a mandatory, two-stage local validation pipeline utilizing sandboxed, project-scoped CLI tools.

1.  **Stage 1 - Structural Syntax (yamllint):** We will utilize `yamllint` (Python) to enforce YAML 1.2 mechanics, consistent indentation, and structural integrity.
2.  **Stage 2 - Semantic Schema (ajv-cli):** We will utilize `ajv-cli` (Node.js) to validate the structurally sound YAML against the official `schema.json` provided by the JSON Resume standard.

**Security & DevSecOps Constraints:**
To mitigate Software Supply Chain vulnerabilities (such as typosquatting on public registries), we explicitly reject the use of globally installed packages (`npm install -g` or global `pip install`). All validation tools must be locally scoped to the repository via a Python Virtual Environment (`.venv`) and a local `node_modules` directory, governed by cryptographically hashed lockfiles (`package-lock.json`).

## Consequences

### Positive

- **Shift-Left Reliability:** Errors are caught locally in milliseconds, drastically improving Mean Time To Recovery (MTTR) and preserving CI/CD compute budgets.
- **Deterministic Pipeline:** The Python build engine is mathematically guaranteed to receive a perfectly formatted payload, eliminating silent UI regressions.
- **Security Posture:** Utilizing localized, locked dependencies prevents global environment pollution and mitigates the risk of executing untrusted, globally hijacked binaries.

### Negative

- **Developer Friction:** Introduces a slight overhead for onboarding new developers, as they must now initialize both Python and Node.js environments before contributing content.
