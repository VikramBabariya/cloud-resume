# Incident Report: INC-001

## OIDC STS Role Assumption Failure (Variable Mismatch)

- **Date of Incident:** 2026-04-27
- **Author:** Vikram Babariya (Cloud/Solutions Architect)
- **Status:** Resolved
- **Severity:** High (Blocking CI/CD Deployment Pipeline)
- **Component:** GitHub Actions CI/CD (`front-end-cicd.yml`) & AWS IAM (OIDC)

### 1. Incident Description & Telemetry

During the final integration phase of the Zero-Trust CI/CD pipeline, the automated deployment workflow failed consistently at the `Configure AWS Credentials (OIDC)` step.

- **Observed Symptom:** The pipeline halted execution and returned the following opaque error trace in the GitHub Actions console:
  > _"Credentials could not be loaded, please check your action inputs: Could not load credentials from any providers"_
- **System Impact:** The failure blocked the generation of ephemeral Security Token Service (STS) credentials, completely halting the "Resume-as-Code" deployment to the S3 Origin and preventing CloudFront cache invalidation.

### 2. Root Cause Analysis (RCA)

Initial diagnostics suspected an Identity Provider (IdP) misalignment or an IAM Trust Policy `Condition` block failure (Confused Deputy mitigation mismatch). However, deep-dive telemetry revealed a configuration drift between the Infrastructure-as-Code (IaC) pipeline definition and the GitHub Secrets environment.

- **The Mechanism of Failure:** The `aws-actions/configure-aws-credentials@v4` action requires a valid Amazon Resource Name (ARN) to pass to AWS STS via the `AssumeRoleWithWebIdentity` API.
- **The Configuration Drift:** \* The CI/CD YAML workflow was explicitly configured to request the ARN using the variable pointer: `${{ secrets.AWS_ROLE_ARN }}`.
  - The actual GitHub Repository Secret was provisioned and stored under the nomenclature: `AWS_DEPLOYMENT_ROLE_ARN`.
- **The Result:** Because GitHub Actions evaluated the missing variable as a null/empty string, an invalid payload was transmitted to AWS STS. The AWS SDK caught the malformed request and bubbled up a generic credential loading failure, masking the underlying syntax mismatch to prevent credential probing.

### 3. Resolution & Mitigation

The incident was mitigated by synchronizing the pipeline configuration with the established secrets taxonomy.

- **Immediate Fix:** The `front-end-cicd.yml` file was updated to perfectly mirror the provisioned GitHub Secret name:
  ```yaml
  # Corrected execution block
  - name: Configure AWS Credentials (OIDC)
    uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: ${{ secrets.AWS_DEPLOYMENT_ROLE_ARN }} # <-- Synchronized variable
      aws-region: ap-south-1
      role-session-name: ${{ github.event.repository.name }}-${{ github.run_id }}
  ```
