# Incident Report: INC-002

## OIDC Trust Policy Rejected Pull Request Tokens

- **Date of Incident:** 2027-01-23
- **Author:** Vikram Babariya (Cloud/Solutions Architect)
- **Status:** Resolved
- **Severity:** High (Blocking PR Review Pipeline)
- **Component:** Terraform IaC Pipeline (`terraform-cicd.yml`) & AWS IAM OIDC Trust Policy

### 1. Incident Description & Telemetry

After adding `src/lambda/**` to the Terraform CI/CD workflow path triggers, a pull request was opened to merge Lambda function changes. The `terraform-cicd.yml` pipeline was correctly triggered but failed immediately at the `Configure AWS Credentials (OIDC)` step with the following authentication rejection:

```
Error: Not authorized to perform sts:AssumeRoleWithWebIdentity
```

- **Observed Symptom:** GitHub Actions runner successfully requested a JWT from GitHub's OIDC provider but AWS STS rejected the token during the `AssumeRoleWithWebIdentity` API call.
- **System Impact:** All pull requests targeting infrastructure or Lambda code changes could not execute `terraform plan`, preventing automated plan review and breaking the shift-left quality gate. Merges to `main` were blocked by CI/CD policy.
- **Timeline:**
  - **T+0m:** PR opened with changes to `src/lambda/visitor_counter.py`
  - **T+1m:** Workflow triggered, OIDC JWT successfully issued by GitHub
  - **T+2m:** AWS STS rejected the JWT with `Not authorized` error
  - **T+15m:** Root cause identified via IAM trust policy inspection
  - **T+30m:** Terraform fix applied via targeted local `terraform apply`
  - **T+35m:** PR re-run succeeded, `terraform plan` posted to PR comment

### 2. Root Cause Analysis (RCA)

The failure was caused by an overly restrictive IAM trust policy on the GitHub Actions deployment role that only permitted tokens from push events to the `main` branch, inadvertently blocking all pull request tokens.

#### The OIDC Token Claim Mismatch

GitHub's OIDC provider issues JWT tokens with a `sub` (subject) claim that varies based on the triggering event:

| Event Type       | JWT `sub` Claim Value                                             |
| ---------------- | ----------------------------------------------------------------- |
| `push` to `main` | `repo:VikramBabariya/zero-trust-rac-platform:ref:refs/heads/main` |
| `pull_request`   | `repo:VikramBabariya/zero-trust-rac-platform:pull_request`        |

#### The Trust Policy Constraint

The original IAM trust policy on the `zero-trust-rac-deployment-role` contained a single statement with a `StringEquals` condition:

```hcl
condition {
  test     = "StringEquals"
  variable = "token.actions.githubusercontent.com:sub"
  values   = ["repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"]
}
```

This constraint mathematically guaranteed that only tokens issued during a push to `main` would be accepted. When a PR-triggered workflow requested credentials, the JWT carried `sub = "repo:...:pull_request"`, which failed the `StringEquals` match and was rejected by AWS STS with an authorization error.

#### Why This Went Undetected Initially

- The `terraform-cicd.yml` workflow was originally scoped to `paths: ["terraform/**"]` only. Early development iterations modified Terraform files directly on `main` or in feature branches that were never opened as PRs, so the trust policy was never exercised in a PR context.
- Adding `src/lambda/**` to the path filter increased the likelihood of PR-triggered runs, immediately exposing the gap.

### 3. Resolution & Mitigation

The trust policy was updated to support both push and pull request events while maintaining strict repository and audience scoping to preserve Zero-Trust security boundaries.

#### Updated Trust Policy (Two-Statement Pattern)

The fix introduced two separate IAM policy statements, each with explicit `StringEquals` conditions:

```hcl
data "aws_iam_policy_document" "deployment_trust" {
  # Statement 1: Push to main (terraform apply runs here)
  statement {
    sid     = "AllowGitHubOIDCPushToMain"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }

  # Statement 2: Pull requests (terraform plan only)
  statement {
    sid     = "AllowGitHubOIDCPullRequest"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:pull_request"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}
```

#### Deployment Procedure

Since the trust policy change was in Terraform but the pipeline itself was broken (chicken-and-egg problem), the fix was applied via a targeted local `terraform apply`:

```bash
# Run from the repo root in PowerShell or CMD
wsl -- bash -c "
  cd \$(wslpath '\$(pwd)')/terraform &&
  export TF_VAR_cloudflare_api_token='<redacted>' &&
  export TF_VAR_cloudflare_zone_id='<redacted>' &&
  export TF_VAR_aws_account_id='<redacted>' &&
  export TF_VAR_notification_email='<redacted>' &&
  terraform apply -target=module.iam -auto-approve
"
```

Using `-target=module.iam` ensured only the IAM resources were updated, minimizing blast radius during the emergency fix.

### 4. Security Posture Analysis

The updated trust policy maintains all Zero-Trust security constraints:

| Security Control                       | Before Fix        | After Fix         |
| -------------------------------------- | ----------------- | ----------------- |
| Cross-repo token reuse blocked         | ✅ Yes            | ✅ Yes            |
| Cross-audience token reuse blocked     | ✅ Yes            | ✅ Yes            |
| Push to non-main branches blocked      | ✅ Yes            | ✅ Yes            |
| Pull request from same repo allowed    | ❌ No             | ✅ Yes            |
| Wildcards in `sub` claim               | ❌ None           | ❌ None           |
| `terraform apply` gated to `push` only | ✅ Workflow-level | ✅ Workflow-level |

The workflow itself provides an additional layer of defense:

```yaml
- name: terraform apply
  if: github.event_name == 'push' && github.ref == 'refs/heads/main'
  run: terraform apply -auto-approve -input=false
```

Even if a malicious actor somehow obtained a PR token that satisfied the trust policy, the `terraform apply` step would never execute because the `if` condition explicitly gates it to push events only. This defense-in-depth pattern ensures that PRs can authenticate for read-only operations (`terraform plan`, state read) but cannot mutate infrastructure.

### 5. Lessons Learned & Future Recommendations

#### What Went Well

- **Explicit error message:** AWS STS returned a clear `Not authorized to perform sts:AssumeRoleWithWebIdentity` error, immediately pointing to the trust policy as the culprit rather than a generic authentication failure.
- **Isolated fix:** Using `-target=module.iam` allowed surgical remediation without risking unrelated infrastructure changes during the incident.
- **No production impact:** The incident only affected the CI/CD pipeline's ability to run `terraform plan` on PRs. The live production infrastructure (CloudFront, Lambda, DynamoDB) was unaffected.

#### What Could Be Improved

- **Pre-deployment testing:** The trust policy was designed and applied based on the initial `push`-only workflow behavior. When the workflow was expanded to support PR triggers, the trust policy should have been updated proactively rather than reactively.
- **Integration test gap:** There is currently no automated test that validates OIDC authentication succeeds for both `push` and `pull_request` events. A synthetic PR opened by a bot could serve as a continuous integration test for this boundary.

#### Action Items

- [x] **Immediate:** Update trust policy to permit `pull_request` tokens (completed 2027-01-23)
- [ ] **Short-term:** Add a GitHub Actions workflow that opens a synthetic PR on a schedule to validate OIDC authentication for PR contexts
- [ ] **Long-term:** Document the OIDC trust policy design in an ADR, explicitly stating which GitHub event types are supported and why
- [ ] **Documentation:** Update `docs/RUNBOOK.md` Section 4 (GitHub Secrets Setup) to note that the trust policy supports both `push` and `pull_request` events

### 6. References

- [GitHub Actions OIDC Token Claims](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect#understanding-the-oidc-token)
- [AWS IAM AssumeRoleWithWebIdentity](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html)
- Terraform module: `terraform/modules/iam/main.tf` (lines 86–127, deployment trust policy)
- Related incident: INC-001 (OIDC variable name mismatch)
