# Tech Stack

## Languages & Runtimes

- **Python 3.12** — build engine (`build.py`), Lambda functions
- **Node.js >= 24.13.x / npm >= 11.6.x** — validation tooling only (no runtime JS framework)
- **YAML** — resume data contract (`data/resume.yaml`)
- **Jinja2** — HTML templating (`src/templates/resume.html.j2`)

## Key Libraries

| Layer  | Package               | Purpose                                                        |
| ------ | --------------------- | -------------------------------------------------------------- |
| Python | `PyYAML==6.0.1`       | YAML parsing — always use `yaml.safe_load()`                   |
| Python | `Jinja2==3.1.3`       | Template rendering with `StrictUndefined` + `autoescape=True`  |
| Python | `markupsafe`          | `Markup()` wrapper for safely injecting raw CSS into templates |
| Node   | `ajv-cli@^3.3.0`      | JSON Schema semantic validation of YAML                        |
| Node   | `prettier@^3.7.4`     | Code formatting (HTML, CSS, JS, JSON, MD)                      |
| Node   | `husky@^9.1.7`        | Git pre-commit hooks                                           |
| Node   | `lint-staged@^16.2.7` | Runs Prettier on staged files                                  |
| Python | `yamllint==1.38.0`    | YAML structural/syntax linting                                 |

## AWS Services

CloudFront (CDN + TLS via ACM) → S3 (private origin, OAC) → API Gateway → Lambda (Python 3.12) → DynamoDB (On-Demand)

DNS: Cloudflare authoritative, DNS-only (grey cloud), CNAME flattening at root.

## CI/CD

GitHub Actions (`.github/workflows/front-end-cicd.yml`), triggered on push to `main`. Authenticates to AWS via OIDC — no static IAM keys anywhere.

## Common Commands

### Environment Setup (run once)

```bash
# Python virtual environment
python3 -m venv .venv
source .venv/bin/activate        # Windows: .\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

# Node tooling
npm ci
```

### Validation (must pass before committing)

```bash
# Formatting check
npx prettier --check "**/*.{html,css,js}"

# YAML syntax (yamllint) + schema (ajv-cli) — both stages
npm run validate

# Run stages individually
npm run validate:syntax     # yamllint only
npm run validate:schema     # ajv-cli only
```

### Build

```bash
# Activate venv first, then compile dist/index.html
source .venv/bin/activate
python build.py
```

### Local Preview

```bash
python3 -m http.server 8000 --directory dist
```

## Code Style

- **Python:** Structured logging via `logging` module (not `print`). Absolute path resolution via `pathlib.Path`. `sys.exit(1)` on any unrecoverable error with a descriptive `logger.critical()` message.
- **YAML:** 2-space indentation, trailing newline, no trailing spaces (enforced by `.yamllint.yaml`). Dates as `"YYYY-MM-DD"` strings.
- **JS/CSS/HTML/JSON/MD:** Prettier enforced — `tabWidth: 2`, `singleQuote: true`, `semi: true`.
- **Jinja2 templates:** `StrictUndefined` is active — every template variable must exist in the data or the build fails. Never disable this.
