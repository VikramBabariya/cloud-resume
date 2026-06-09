# ADR 0008: Strategic Domain Name Ingress and Registrar Procurement Selection

**Status:** APPROVED / ACCEPTED  
**Epic:** Portfolio Technical Identity & Ingress Governance  
**Primary Driver:** Mean Time To Evaluation (MTTE) Optimization, FinOps Total Cost of Ownership (TCO) Reduction, and Edge-Network Zero-Trust Enforcement.

## Context

The "Zero-Trust RaC Platform" operates at a strict SRE Maturity Level 3 baseline, incorporating OIDC Federated Identity, resource-scoped Principle of Least Privilege (PoLP), and Idempotent Deployments via automated pipelines. However, the platform's public-facing ingress point previously utilized a generic identifier (`vb-web.in`).

To maximize portfolio value for the Indian Cloud/DevOps job market, the public-facing entry point requires optimization to drastically lower MTTE (Mean Time To Evaluation) for external stakeholders (recruiters and Principal Engineers). Concurrently, this public boundary represents the outermost perimeter of our Zero-Trust architecture, demanding rigorous edge security without violating our lean financial constraints (the $6 USD/month or ~₹500 INR operational budget).

## Options Considered

### Option 1: Legacy Identifier Re-use (`vb-web.in`)

- **Pros:** Zero additional procurement overhead or manual routing migration required.
- **Cons:** Weak technical signal. The "web" suffix subconsciously categorizes the candidate as a frontend developer rather than an infrastructure engineer, introducing immense cognitive friction and severely bloating MTTE.

### Option 2: Purely Architectural Domain (`rac-platform.dev`)

- **Pros:** High level of Artifact Hygiene by establishing a direct 1:1 match with the GitHub repository name.
- **Cons:** Obfuscates personal branding. Mimics a SaaS product or open-source tool rather than an individual portfolio, creating misalignment during initial human evaluation.

### Option 3: Role-Specific Personal Domain (`vikram-sre.dev`) via Cloudflare Registrar

- **Pros:** Provides an instantaneous, high-fidelity technical signal. Merges personal identity with target engineering discipline to instantly minimize MTTE.
- **Cons:** Introduces an upfront domain registration cost, requiring rigorous FinOps vetting to ensure compliance with the platform's lean operational baseline.

## Decision

We will adopt **Option 3: `vikram-sre.dev`** as the definitive public ingress domain name, procured exclusively through Cloudflare Registrar.

## Technical and Strategic Justification

- **Edge-Network Zero-Trust Enforcement via Mandatory HSTS:**
  The `.dev` Top-Level Domain (TLD) is hardcoded on the global HSTS (HTTP Strict Transport Security) preload list maintained by modern browsers. This architectural characteristic forces all client traffic to interact with our platform over an encrypted HTTPS connection from the very first bit transmitted, completely mitigating protocol downgrade attacks, man-in-the-middle (MitM) hijacking, and cookie sniffing. By attaching this domain to our global CloudFront CDN edge, we ensure our Zero-Trust data-in-transit security posture is cryptographically guaranteed at the registrar boundary.

- **Wholesale Cloudflare Procurement Supporting Lean FinOps & TCO:**
  Standard registrars engage in "bait-and-switch" pricing models, offering low initial registration rates offset by inflated, compounding annual renewal costs. Cloudflare Registrar operates at zero-markup wholesale pricing, passing the exact ICANN registry cost directly to the user. This drives the domain's three-year Total Cost of Ownership (TCO) down to its mathematical minimum (~₹1,200 INR annually), equating to an amortized monthly infrastructure overhead of approximately $1.20 USD. This fits comfortably within our strict cost boundaries without impacting the compute/secrets layer budgets.

- **Immediate MTTE Reduction:**
  In the 6-second window a technical manager utilizes to screen a resume, the identifier `vikram-sre.dev` acts as an immediate, programmatic filter bypass. It signals specialized competence in site reliability, systems engineering, and modern cloud deployment paradigms before the reviewer even audits the underlying codebase.

## Consequences

### The Good (Strategic Gains):

- **Airtight Artifact Hygiene:** The repository configuration, public profile, and network URL now exist in perfect narrative synergy, projecting an obsessive attention to detail expected of a high-level architect.
- **Zero-Downtime Migration Model:** Adopting a professional registrar allows for seamless integration with AWS Route 53 using custom name server delegations, preserving our infrastructure-as-code compatibility.

### The Bad (Operational Overheads & Mitigations):

- **The Broken Link Hazard:** Changing the URL risks creating dangling pointers on older resume variants.
- **Mitigation:** We will implement an automated HTTP 301 Permanent Redirect at our CloudFront edge network, mapping any legacy `vb-web.in` ingress traffic to the new high-signal `vikram-sre.dev` origin, successfully preventing any availability dips or MTTR spikes.
