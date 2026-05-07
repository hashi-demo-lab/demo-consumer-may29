# Consumer Module Uplift -- Implementation Plan

**Branch**: feat/consumer-module-uplift
**Date**: 2026-03-06
**Issue**: hashi-demo-lab/terraform-agentic-workflows#3 (Use Case 1)
**Status**: Draft

---

## 1. Problem Statement

When a module author publishes a new version to the HCP Terraform private registry, **consumers** of that module must update their workspace code. The change scope ranges from trivial (bump a version constraint) to complex (new required variables, removed outputs, restructured interfaces). Existing tools like Dependabot can detect new versions but provide **zero semantic understanding** of what changed -- especially for private registry modules which lack changelogs.

The automation gap: no tool today reads the module interface diff, maps breaking changes to consumer code, rewrites HCL, and validates the result. This is precisely the gap an agentic workflow can fill.

---

## 2. Scope

**In scope (Use Case 1 only)**:
- Consumer-side module version upgrades (workspace code that calls private registry modules)
- Detection via Dependabot + fallback scanner
- Deterministic risk assessment from plan output
- Risk-based decision framework (auto-merge / needs-review / breaking-change)
- Interactive `@claude` follow-up on PRs for complex upgrades
- Optional Copilot code review as complementary passive reviewer
- Post-merge apply to HCP Terraform
- Module update tracker dashboard

**Out of scope (Use Case 2 -- separate issue)**:
- Producer-side module uplift (upgrading the module itself)
- Provider version upgrades within modules
- Breaking change detection for module authors
- Migration guide generation

---

## 3. Architecture Overview

### Single Connected Pipeline

The consumer uplift workflow operates as a **unified GitHub Actions pipeline** with two trigger modes in a single workflow file. There is no separate CLI skill -- the entire workflow lives in CI with interactive escalation built in.

```
Dependabot PR / Fallback Scanner PR
       |
       v
┌──────────────────────────────────────────────────┐
│  terraform-consumer-uplift.yml (auto-trigger)    │
│                                                  │
│  Job 1: CLASSIFY                                 │
│    Parse git diff, detect semver type            │
│    (patch / minor / major)                       │
│                                                  │
│  Job 2: VALIDATE                                 │
│    terraform fmt, init, validate, tflint, plan   │
│    Exit 0 → close PR (already current)           │
│    Exit 1 → label breaking, block                │
│    Exit 2 → upload plan artifact, continue       │
│                                                  │
│  Job 3: RISK ASSESSMENT (deterministic)          │
│    ├── Input: version_type + plan_summary        │
│    ├── Matrix lookup (4 rules)                   │
│    └── Output: decision + risk_level JSON        │
│                                                  │
│  Job 4: DECISION                                 │
│    ├── risk:low → auto-merge (squash)            │
│    ├── risk:medium → label + request review      │
│    └── risk:high/critical → block + analysis     │
└──────────────────────────────────────────────────┘
       |
       v  (if human review needed)
┌──────────────────────────────────────────────────┐
│  Same workflow, issue_comment trigger            │
│  @claude mention on PR for interactive follow-up │
│    ├── Deep analysis with full MCP access        │
│    ├── Can make code changes + push              │
│    ├── Can re-run interface diff                 │
│    └── Responds as PR comment                    │
└──────────────────────────────────────────────────┘
       |
       v  (on merge to main)
┌──────────────────────────────────────────────────┐
│  terraform-apply.yml             │
│  Upload config → POST /api/v2/runs               │
│  Poll completion → comment results on PR         │
└──────────────────────────────────────────────────┘
```

### Why No Separate CLI Skill

The original plan had two independent modes (CI pipeline + interactive CLI skill). This created duplication and a disconnect. The connected architecture eliminates both problems:

| Concern | How It's Solved |
|---------|----------------|
| **Automated routine patches** | Jobs 1-4 run on every Dependabot PR |
| **Complex upgrades needing human judgment** | `@claude` mention on blocked/review-needed PRs |
| **Code adaptation** | claude-code-action pushes fixes directly to PR branch |
| **Deep follow-up analysis** | Interactive mode in same workflow, full MCP access |
| **No logic duplication** | Single agent prompt, single decision matrix, one place to maintain |

### Complementary Reviewers

| Tool | Role | Trigger |
|------|------|---------|
| **claude-code-action** | Active: analyze, adapt code, decide, merge | `pull_request` + `issue_comment` |
| **GitHub Copilot** | Passive: general code quality review | Repo ruleset (auto-review on PR) |

Copilot runs independently via repository rulesets (Settings > Rulesets), not a workflow YAML. It provides broad code quality feedback while Claude handles the Terraform-specific uplift analysis.

---

## 4. Decision Matrix

Risk classification drives the automated decision. The matrix is applied deterministically by a bash script in Job 3.

```
                              PATCH/MINOR     MAJOR
                              -----------     -----
No adds, no changes           AUTO-MERGE      AUTO-MERGE
                              risk:low        risk:low

Adds only, no changes         NEEDS-REVIEW    NEEDS-REVIEW
to existing                   risk:low        risk:medium

Changes to existing           NEEDS-REVIEW    NEEDS-REVIEW
(with or without adds)        risk:medium     risk:high

Any DESTROY/REPLACE           BREAKING-       BREAKING-
in plan                       CHANGE          CHANGE
                              risk:high       risk:critical

Plan fails (exit 1)           BREAKING-       BREAKING-
                              CHANGE          CHANGE
                              risk:high       risk:critical
```

"Adds" = new resources created. "Changes" = modifications to existing resources.

**Key principles:**
1. Only zero-change plans (no adds, no changes) are auto-merged
2. Adds-only (no changes to existing) is low risk but still requires review
3. Changes to existing resources always require review at medium risk or higher
4. Any DESTROY or REPLACE action classifies as BREAKING-CHANGE (merge blocked)
5. Plan failures (exit 1) always classify as BREAKING-CHANGE
6. Major version bumps escalate risk by one tier (low→medium, medium→high, high→critical)
7. The matrix is fully deterministic — no AI involved in risk assessment

---

## 5. Artifacts to Create

### 5.1 GitHub Actions Workflows

| File | Purpose |
|------|---------|
| `.github/workflows/terraform-consumer-uplift.yml` | Unified workflow: classify, validate, AI analysis, decision + @claude interactive |
| `.github/workflows/terraform-apply.yml` | Post-merge apply to HCP Terraform + rollback on failure |
| `.github/workflows/module-update-tracker.yml` | *(Phase D — optional)* Self-updating dashboard issue aggregating pending upgrades |

**Key workflow design:**
- Single file combines `pull_request` (automation) and `issue_comment` (interactive) triggers
- Jobs 1-4 use `if: github.event_name == 'pull_request'`
- Interactive job uses `if: contains(github.event.comment.body, '@claude')`
- Job 3 applies the decision matrix deterministically. AI is reserved for `@claude` interactive follow-up.
- claude-code-action can push code changes directly to the PR branch (`contents: write`)
- Concurrency groups per-branch prevent race conditions

### 5.2 CI Agent Definition

| File | Purpose |
|------|---------|
| `.github/agents/module-upgrade-remediation.md` | Claude Code Action agent prompt for automated analysis |

The agent prompt defines the analysis capabilities for interactive `@claude` follow-up on PRs. It is NOT used in the automated pipeline (Job 3 is deterministic). Key features:
- Uses Terraform MCP tools (`get_private_module_details`, `search_private_modules`)
- Can make code changes (add variables, fix output references, update version constraints)
- Conservative bias: `needs-review` over `auto-merge` when uncertain
- Maximum 15 turns to control cost

### 5.3 Supporting Scripts

| File | Purpose |
|------|---------|
| `.foundations/scripts/bash/classify-version-bump.sh` | Parse git diff to classify semver bump type (patch/minor/major) |
| `.foundations/scripts/bash/scan-module-versions.sh` | TFC API fallback scanner for module version detection |

**classify-version-bump.sh**: Extracts old/new version constraints from `git diff`, computes semver delta, outputs JSON with module name, old version, new version, and bump type.

**scan-module-versions.sh**: Queries `GET /api/v2/organizations/{org}/registry-modules` to discover new module versions. Covers edge cases Dependabot misses (submodule paths like `cloudwatch//modules/metric-alarm`). Creates branches and PRs in the same format as Dependabot for pipeline compatibility.

### 5.4 Configuration Files

| File | Purpose |
|------|---------|
| `.github/dependabot.yml` | Private registry module scanning (monthly schedule) |
| `.mcp-ci.json` | MCP server config for CI (`npx`, no Docker) |

**Dependabot config:**
```yaml
version: 2
registries:
  terraform-private:
    type: terraform-registry
    url: https://app.terraform.io
    token: ${{ secrets.TFE_TOKEN_DEPENDABOT }}
updates:
  - package-ecosystem: terraform
    directory: "/"
    schedule:
      interval: monthly
    registries:
      - terraform-private
```

**MCP CI config** (npx for faster cold start, no Docker dependency):
```json
{
  "mcpServers": {
    "terraform": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/terraform-mcp-server@latest", "--toolsets=all"],
      "env": { "TFE_TOKEN": "${TFE_TOKEN}" }
    }
  }
}
```

### 5.5 Diagram

| File | Purpose |
|------|---------|
| `.foundations/design/consumer-uplift-workflow.html` | Interactive visual diagram of the connected pipeline |

---

## 6. Workflow Detail

### Job 1: Classify

Parses the git diff to extract old/new version constraints and determine semver bump type. Uses `classify-version-bump.sh`. Detects whether the PR is from Dependabot or the fallback scanner.

**Outputs**: `version_type` (patch/minor/major), `modules_changed` (JSON array), `is_dependabot` (boolean)

### Job 2: Validate

Runs deterministic Terraform validation. This is the gate that determines whether AI analysis is needed.

| Step | Tool | Gate |
|------|------|------|
| Format check | `terraform fmt -check` | Block on failure |
| Init | `terraform init` (with TFE_TOKEN) | Block on failure |
| Validate | `terraform validate` | Block on failure |
| Lint | `tflint` | Block on failure |
| Plan | `terraform plan -detailed-exitcode` | Exit 0: close PR, Exit 1: label breaking, Exit 2: continue |

**Prerequisite**: `hashicorp/setup-terraform` must use `terraform_wrapper: false` — the default wrapper converts exit code 2 to 1 (see Decision D7).

**Plan exit code handling:**
- **Exit 0** (no changes): Post a comment explaining the workspace already reflects this version (e.g., applied via another path), then close the PR. This prevents silent closures and leaves an audit trail.
- **Exit 1** (error): Label `breaking-change`, block merge, post error details.
- **Exit 2** (changes detected): Upload plan artifact, continue to Job 3.

**Outputs**: `plan_exitcode`, `resource_changes` (summary)

### Job 3: Risk Assessment

Only runs if plan exit code is 2 (changes detected). A deterministic bash script applies the decision matrix using inputs from Jobs 1-2:

**Inputs:**
- `version_type` (patch/minor/major) from Job 1
- `plan_summary` (add/change/destroy/replace/total) from Job 2

**Matrix Rules (checked in priority order):**
1. If destroy > 0 or replace > 0 → BREAKING-CHANGE (high/critical)
2. If total changes = 0 → AUTO-MERGE (low)
3. If total changes > 0 → NEEDS-REVIEW (medium for patch/minor, high for major)
4. Apply semver column (patch/minor/major) for risk level

**Output:** Same structured JSON format as before, but with empty `breaking_changes`, `security_findings`, `adaptations_applied`, and `interface_diff` fields. These fields are preserved for compatibility with Job 4 but are not populated by the deterministic pipeline.

No claude-code-action, no MCP tools, no AI. The risk assessment is fully scripted.

### Job 4: Decision

Reads the structured JSON output from Job 3 and takes action:

| Decision | Action |
|----------|--------|
| `auto-merge` + `risk:low` | Apply labels, squash merge |
| `needs-revalidation` | Apply labels, post "re-validating after adaptations" comment, wait for re-triggered pipeline |
| `needs-review` | Apply labels, request reviewer, post analysis comment |
| `breaking-change` | Apply labels, block merge, post detailed analysis |

PR title is prefixed with emoji + semver tag for visual distinction:
- `[patch]` Low-risk patch
- `[minor]` Minor version bump
- `[MAJOR]` Major version bump (always needs review)
- `[BREAKING]` Plan failed (exit 1)

### Interactive Fix (@claude)

When a PR is labeled `needs-review` or `breaking-change`, the decision comment instructs the user to comment `@claude` to fix the code. The same workflow handles this via the `issue_comment` trigger:

- Checks out PR branch and runs `terraform plan` to capture current errors
- Uses Terraform MCP tools to compare old vs new module interfaces
- **Fixes consumer code**: adds missing variables, updates removed outputs, fixes type mismatches
- Validates fixes with `terraform validate` and `terraform plan`
- Commits and pushes to the PR branch — triggering pipeline re-run
- Never approves or merges — the pipeline re-assesses risk after the fix

### Post-Merge Apply

Separate workflow triggered on push to main when `.tf` files change:
1. Resolve workspace ID via TFC API
2. Upload configuration tarball
3. Create run (`POST /api/v2/runs`)
4. Poll until terminal state (applied/errored)
5. Confirm run when it reaches confirmable state
6. Comment results on the merged PR

**On apply failure** (see Decision D6):
7. Comment error details + TFC run link on the merged PR
8. Create incident issue (`incident:apply-failure`) with error log, workspace/run IDs, and diff
9. Auto-generate a draft rollback PR (`git revert`) — this PR goes through the normal pipeline
10. Tag CODEOWNERS on the incident issue

### Module Update Tracker

Self-updating GitHub issue that aggregates all pending Dependabot PRs:
- Triggers on PR events (opened, closed, reopened, labeled)
- Queries all open PRs with `dependabot/terraform/` prefix
- Builds markdown dashboard: PR number, title, version type, risk level, recommendation, age
- Closes tracker when no pending PRs; reopens when new ones arrive
- Pinned issue for visibility

---

## 7. Integration Points

### With Existing SDD Framework

| Component | Integration |
|-----------|-------------|
| **Consumer constitution** | No changes -- uplift produces consumer code, same rules apply |
| **AGENTS.md** | Add consumer uplift workflow reference |
| **.mcp-ci.json** | Already exists -- verify or update for CI use |
| **validate-env.sh** | Not used (CI handles prerequisites) |

### With HCP Terraform

| Integration | Details |
|-------------|---------|
| **Private registry** | MCP `get_private_module_details` for interface diff |
| **Workspace** | Plan + apply in target workspace |
| **Variable sets** | Shared credentials for provider auth |
| **Run API** | `POST /api/v2/runs` for post-merge apply |
| **Registry API** | `GET /api/v2/organizations/{org}/registry-modules` for fallback scanner |

### With GitHub

| Integration | Details |
|-------------|---------|
| **Dependabot** | `terraform-registry` ecosystem for private module detection |
| **claude-code-action** | PR-triggered analysis + interactive @claude follow-up |
| **Copilot** | Optional passive code review via repository rulesets |
| **PR labels** | `risk:low/medium/high/critical`, `auto-merge`, `needs-review`, `breaking-change` |
| **PR comments** | Structured analysis summaries with decision rationale |
| **Tracker issue** | Self-updating dashboard of pending module upgrades |

---

## 8. Implementation Order

### Phase A: Scripts & Configuration

1. Create `classify-version-bump.sh`
2. Create `scan-module-versions.sh`
3. Create/update `.mcp-ci.json` for CI
4. Create `.github/dependabot.yml`

### Phase B: Workflows & Agent

5. Create `module-upgrade-remediation.md` CI agent definition
6. Create `terraform-consumer-uplift.yml` (main pipeline + interactive)
7. Create `terraform-apply.yml` (post-merge apply + rollback on failure)

### Phase C: Documentation & Diagram

8. Create `consumer-uplift-workflow.html` visual diagram
9. Update `AGENTS.md` with consumer uplift workflow reference

### Phase D: Optional Enhancements (Deferred)

10. Create `module-update-tracker.yml` (dashboard issue)
11. Copilot ruleset configuration guide

---

## 9. Key Design Decisions

### D1: Single connected pipeline, no CLI skill

**Decision**: Everything runs in GitHub Actions. No `/tf-consumer-uplift` CLI skill.

*Rationale*: The original plan had two independent modes creating duplication and disconnect. The connected architecture uses `claude-code-action` for automated analysis on PR creation and `@claude` mentions for interactive follow-up on the same PR. This eliminates logic duplication and keeps the workflow in one place.

### D2: Structured JSON output as the bridge

**Decision**: Use `--json-schema` to produce structured output that drives deterministic downstream steps.

*Rationale*: The AI analysis produces a JSON recommendation. Downstream GitHub Actions steps use `fromJSON()` to parse fields and make deterministic decisions (label, merge, block). This separates the "thinking" (AI) from the "acting" (GitHub API) with a clear, auditable contract between them.

### D3: Sonnet for automation, @claude for deep follow-up

**Decision**: Automated pipeline uses Sonnet for cost efficiency. Interactive `@claude` also uses Sonnet but can be overridden.

*Rationale*: CI runs on every Dependabot PR -- cost matters. The 5 sub-analyses are structured tasks that don't require Opus. For truly complex cases, users can escalate to human review or adjust the model in the workflow config.

### D4: Copilot as complementary passive reviewer

**Decision**: Enable GitHub Copilot code review via repository rulesets alongside the Claude pipeline.

*Rationale*: Copilot provides broad code quality feedback (style, bugs, general issues). Claude handles the Terraform-specific uplift analysis (interface diff, MCP tools, risk classification). They don't interfere -- each posts independently.

### D5: Two-pass validation when AI adapts code

**Decision**: If Job 3 pushes code changes (step 5B), Job 4 sets the decision to `needs-revalidation` instead of a final verdict. The pushed changes trigger a `synchronize` event, which re-runs the full pipeline (Jobs 1-4) on the adapted code. Only the second pass — where no further adaptations are needed — produces a final decision.

*Rationale*: The plan from the first pass is stale after AI code changes. Auto-merging based on a stale plan is unsafe. The two-pass approach guarantees the final decision is based on a plan that matches the actual code. The `adaptations_applied` field in the structured JSON output distinguishes first-pass (adaptations made) from second-pass (no adaptations) runs. This adds one extra pipeline run (~2-4 minutes) but ensures correctness.

**Implementation**: Job 4 checks `if adaptations_applied is not empty → label needs-revalidation, skip merge/block, wait for re-trigger`. The re-triggered run sees clean code, produces a fresh plan, and makes the final decision.

### D6: Rollback strategy on failed applies

**Decision**: On apply failure, the pipeline does NOT auto-revert the merge. Instead, it creates an incident issue with full context and a one-click rollback PR.

*Rationale*: Auto-reverting merges at enterprise scale is dangerous — it can cascade through dependent workspaces, trigger unexpected destroys, and bypass change management. The safer pattern is:

1. **Immediate**: Comment on the merged PR with apply error details and link to the TFC run
2. **Escalate**: Create a GitHub issue labeled `incident:apply-failure` with the error log, workspace ID, run ID, and the git diff that caused the failure
3. **Rollback PR**: Auto-generate a draft PR that reverts the merge commit (using `git revert`), pre-titled `[ROLLBACK] Revert module upgrade: {module}@{version}`
4. **No auto-merge on rollback**: The rollback PR goes through the same pipeline (classify → validate → plan) to ensure the revert is safe before merging
5. **Notify**: Tag the configured team/CODEOWNERS on the incident issue

This gives the ops team full context, a prepared rollback path, and human control over the recovery. The rollback PR also validates through the pipeline, preventing a bad revert from making things worse.

### D7: Workspace execution mode compatibility

**Decision**: The pipeline supports CLI-driven workspaces as the primary mode, with API-driven as a documented alternative. VCS-backed workspaces are explicitly out of scope for the automated pipeline.

*Rationale*: Research into HCP Terraform workspace types reveals fundamental differences in how each mode interacts with CI:

| Mode | `terraform plan` from CI | `terraform apply` from CI | `-detailed-exitcode` | Provider Creds |
|------|-------------------------|--------------------------|---------------------|----------------|
| **CLI-driven** | Yes (remote execution) | Yes (`-auto-approve`) | Yes (with `terraform_wrapper: false`) | Workspace dynamic creds (OIDC) |
| **API-driven** | N/A (use Runs API) | N/A (confirm via API) | N/A (check run status) | Workspace dynamic creds (OIDC) |
| **VCS-backed** | Speculative only (read-only) | Blocked ("Apply not allowed") | Limited | Workspace dynamic creds (OIDC) |
| **Agent** | Same as chosen workflow | Same as chosen workflow | Same as chosen workflow | Agent infrastructure |

**CLI-driven** is the natural fit because:
- `terraform plan -detailed-exitcode` works natively (exit 0/1/2 flow in Job 2)
- `terraform apply -auto-approve` works for post-merge apply
- Provider credentials stay in the workspace (dynamic credentials via OIDC) — the CI runner never needs AWS creds
- Standard `hashicorp/setup-terraform` action with `terraform_wrapper: false` handles authentication

**VCS-backed is incompatible** because:
- `terraform apply` is blocked from CLI on VCS-connected workspaces
- VCS webhooks would trigger duplicate runs alongside the CI pipeline
- The pipeline's post-merge apply (D6) requires programmatic apply control

**API-driven alternative**: For teams preferring pure API workflows, the pipeline can use `hashicorp/tfc-workflows-github` actions instead of CLI commands. The Validate job would use `upload-configuration` + `create-run` (speculative) instead of `terraform plan`. Decision logic maps run statuses (`planned`, `errored`) instead of exit codes. This is documented as a configuration option, not a separate pipeline.

**Critical implementation note**: The `hashicorp/setup-terraform` action must set `terraform_wrapper: false`. The default wrapper intercepts exit codes, converting exit code 2 (changes detected) to exit code 1 (error) via its `setFailed()` call. Without disabling the wrapper, Job 2's plan exit code gate will malfunction.

### D8: No separate constitution for uplift

**Decision**: Reuse the existing consumer constitution. No `uplift-constitution.md`.

*Rationale*: Uplift produces consumer code -- the same rules apply. The consumer constitution already covers version management (Section 4.3). Adding a separate constitution would create maintenance burden.

---

## 10. What We're NOT Adopting From the External Repo

| External Repo Pattern | Our Approach | Reason |
|----------------------|--------------|--------|
| Hardcoded TFC org/workspace | Environment variables | Portability across organizations |
| Separate classify script in workflow | Shared script in `.foundations/scripts/bash/` | Reusable across repos |
| No interactive follow-up | `@claude` mention in same workflow | Escalation path for complex upgrades |
| No complementary reviewer | Optional Copilot code review | Defense in depth |
| No module tracker | Self-updating tracker issue | Org-wide visibility of pending upgrades |
| `terraform_wrapper: false` assumed | Explicit in setup | Reproducibility |

---

## 11. Authentication & Secrets

| Secret | Purpose | Scope |
|--------|---------|-------|
| `TFE_TOKEN` | Terraform init, plan, MCP tools, TFC API | GitHub Actions |
| `TFE_TOKEN_DEPENDABOT` | Private registry version detection | Dependabot (read-only) |
| `ANTHROPIC_API_KEY` | claude-code-action API authentication | GitHub Actions |
| `GITHUB_TOKEN` | PR operations (labels, merge, comments) | Auto-provided |

**Provider credentials (AWS, Azure, GCP)** are NOT stored in GitHub Actions secrets. They are managed by HCP Terraform's dynamic provider credentials (OIDC) configured on the workspace. When the CI pipeline runs `terraform plan`, execution happens remotely in HCP Terraform's environment, which generates workload identity tokens and exchanges them for temporary cloud provider credentials. The GitHub Actions runner never needs cloud provider access (see Decision D7).

---

## 12. Success Criteria

1. Dependabot PR triggers the pipeline and produces a structured analysis
2. Zero-change plans auto-merge; adds-only gets low-risk review; changes to existing get medium-risk review
3. High-risk changes are blocked with detailed analysis and `@claude` follow-up instructions
4. `@claude` mention on a blocked PR provides interactive deep analysis with MCP tools
5. Post-merge apply successfully triggers HCP Terraform run
6. Module tracker dashboard accurately reflects pending upgrades
7. Decision matrix correctly maps semver type + breaking changes + plan diff to risk level
8. Visual diagram accurately represents the connected architecture
