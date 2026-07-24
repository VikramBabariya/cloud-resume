# Project Structure

```
zero-trust-rac-platform/
├── data/
│   └── resume.yaml          # Single source of truth — all resume content lives here
├── src/
│   ├── templates/
│   │   └── resume.html.j2   # Jinja2 template — presentation layer only
│   └── static/
│       └── style.css        # CSS — injected inline at build time (Critical Path CSS)
├── dist/                    # Compiled output — NEVER edit manually, always gitignored
│   └── index.html           # Generated artifact from build.py
├── docs/
│   ├── schema.json          # JSON Resume schema used by ajv-cli for validation
│   ├── RUNBOOK.md           # Operational runbook: local setup, deploy, DR procedures
│   ├── RESUME_SCHEMA.md     # Data contract documentation
│   ├── SECURITY.md          # Security posture documentation
│   ├── adr/                 # Architecture Decision Records (ADR 0001–0009)
│   ├── architecture/
│   │   ├── source/          # Diagrams-as-Code (Mermaid) source files
│   │   └── export/          # Rendered diagram images (PNG)
│   └── incidents/           # Post-incident reviews (INC-NNN format)
├── .github/
│   └── workflows/
│       ├── front-end-cicd.yml  # Frontend pipeline — build, validate, deploy on push to main
│       └── terraform-cicd.yml  # IaC pipeline — fmt, validate, checkov, plan (PR), apply (main)
├── .husky/                  # Git hooks — pre-commit runs lint-staged (Prettier)
├── .venv/                   # Python virtual environment — never commit
├── node_modules/            # Node tooling — never commit
├── build.py                 # Python SSG build engine — compiles YAML + template → dist/
├── requirements.txt         # Pinned Python dependencies
├── package.json             # Node scripts: validate, validate:syntax, validate:schema
├── package-lock.json        # Locked Node dependency tree — always commit
├── .yamllint.yaml           # yamllint config: 2-space indent, no trailing spaces
├── .prettierrc              # Prettier config: tabWidth 2, singleQuote, semi
└── terraform/               # Infrastructure as Code — first-class project artifact
    ├── main.tf              # Root: module compositions, backend config, FinOps budget
    ├── variables.tf         # All root variables (sensitive inputs marked sensitive=true)
    ├── outputs.tf           # Root outputs (sensitive outputs marked sensitive=true)
    ├── providers.tf         # AWS (ap-south-1 + us-east-1 alias), Cloudflare
    ├── versions.tf          # required_terraform >= 1.9.0, provider constraints
    ├── terraform.tfvars.example  # Documented variable examples — never commit real values
    └── modules/
        ├── state-backend/   # S3 state bucket (SSE-KMS, versioning) + DynamoDB lock table
        ├── cdn/             # S3 origin, OAC, ACM certificate (us-east-1), CloudFront
        ├── compute/         # DynamoDB visitor-count table, Lambda, API Gateway HTTP API
        ├── dns/             # Cloudflare CNAME records (apex, www, ACM validation)
        └── iam/             # Lambda execution role, GitHub OIDC provider, deployment role
```

## Key Conventions

- **`data/` vs `dist/`:** `data/resume.yaml` is source; `dist/index.html` is output. Never manually edit `dist/`.
- **`src/` is pure presentation:** Template and CSS have no business logic. Data comes entirely from `resume.yaml` via `build.py`.
- **`terraform/` is a first-class artifact:** Treat it like `src/` — all changes go through a PR with a `terraform plan` comment. Never run `terraform apply` locally against prod unless executing a bootstrap or incident-recovery procedure documented in the RUNBOOK. All `terraform` commands on Windows must use WSL (see `tech.md`).
- **`docs/adr/`:** New architectural decisions get an ADR. Filename format: `NNNN-short-title.md`. Increment the number from the last existing ADR.
- **`docs/incidents/`:** Post-incident reviews follow `INC-NNN-short-description.md` format.
- **Architecture diagrams:** Source (Mermaid) lives in `docs/architecture/source/`; exported PNGs go in `docs/architecture/export/`. Always update source before updating exports.
- **No global installs:** All tooling is project-local (`.venv` for Python, `node_modules` for Node). This is a hard security constraint — see ADR 0006.
- **`dist/` is always ephemeral:** The CI/CD pipeline regenerates it on every run. Local `dist/` builds are for preview only.
