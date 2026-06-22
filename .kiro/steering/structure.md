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
│   ├── adr/                 # Architecture Decision Records (ADR 0001–0008)
│   ├── architecture/
│   │   ├── source/          # Diagrams-as-Code (Mermaid) source files
│   │   └── export/          # Rendered diagram images (PNG)
│   └── incidents/           # Post-incident reviews (INC-NNN format)
├── .github/
│   └── workflows/
│       └── front-end-cicd.yml  # The only CI/CD pipeline — deploys on push to main
├── .husky/                  # Git hooks — pre-commit runs lint-staged (Prettier)
├── .venv/                   # Python virtual environment — never commit
├── node_modules/            # Node tooling — never commit
├── build.py                 # Python SSG build engine — compiles YAML + template → dist/
├── requirements.txt         # Pinned Python dependencies
├── package.json             # Node scripts: validate, validate:syntax, validate:schema
├── package-lock.json        # Locked Node dependency tree — always commit
├── .yamllint.yaml           # yamllint config: 2-space indent, no trailing spaces
└── .prettierrc              # Prettier config: tabWidth 2, singleQuote, semi
```

## Key Conventions

- **`data/` vs `dist/`:** `data/resume.yaml` is source; `dist/index.html` is output. Never manually edit `dist/`.
- **`src/` is pure presentation:** Template and CSS have no business logic. Data comes entirely from `resume.yaml` via `build.py`.
- **`docs/adr/`:** New architectural decisions get an ADR. Filename format: `NNNN-short-title.md`. Increment the number from the last existing ADR.
- **`docs/incidents/`:** Post-incident reviews follow `INC-NNN-short-description.md` format.
- **Architecture diagrams:** Source (Mermaid) lives in `docs/architecture/source/`; exported PNGs go in `docs/architecture/export/`. Always update source before updating exports.
- **No global installs:** All tooling is project-local (`.venv` for Python, `node_modules` for Node). This is a hard security constraint — see ADR 0006.
- **`dist/` is always ephemeral:** The CI/CD pipeline regenerates it on every run. Local `dist/` builds are for preview only.
