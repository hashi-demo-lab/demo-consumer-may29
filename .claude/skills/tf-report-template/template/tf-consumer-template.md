# Deployment Report: {{PROJECT_NAME}}

| Field         | Value                |
| ------------- | -------------------- |
| Branch        | {{BRANCH}}           |
| Date          | {{DATE}}             |
| Provider      | {{PROVIDER_VERSION}} |
| HCP Workspace | {{WORKSPACE}}        |

## Modules Composed

| Module          | Registry Source                                | Version     | Status        |
| --------------- | ---------------------------------------------- | ----------- | ------------- |
| {{MODULE_NAME}} | app.terraform.io/{{ORG}}/{{NAME}}/{{PROVIDER}} | {{VERSION}} | {{PASS/FAIL}} |

**Summary**: {{COUNT}} modules composed

## terraform validate

**Result**: {{CLEAN / ERRORS}}

{{If errors, list each as a bullet: file:line -- message}}

## terraform fmt -check

**Result**: {{FORMATTED / NEEDS FORMATTING}}

{{If unformatted, list files as bullets}}

## tflint

**Result**: {{CLEAN / FINDINGS}}

{{If FINDINGS, list each as a bullet: file:line -- rule -- message}}

## trivy config

| Metric   | Count |
| -------- | ----- |
| Total    | {{N}} |
| Defects  | {{N}} |
| Accepted | {{N}} |

### Defects (block deployment)

| AVD-ID     | Severity                     | File:Line     | Description     |
| ---------- | ---------------------------- | ------------- | --------------- |
| {{AVD-ID}} | {{CRITICAL/HIGH/MEDIUM/LOW}} | {{file:line}} | {{description}} |

### Accepted Risks (do not block deployment)

| AVD-ID     | Severity     | File:Line     | Description     | Justification (design ref)                        |
| ---------- | ------------ | ------------- | --------------- | ------------------------------------------------- |
| {{AVD-ID}} | {{severity}} | {{file:line}} | {{description}} | {{Section and rationale from consumer-design.md}} |

{{Accepted risks are design decisions documented in consumer-design.md Section 2 or 4.
They are tracked but do not block deployment.}}

## Run Tasks

**Total tasks**: {{N}} | Passed: {{N}} | Failed: {{N}} | Errored: {{N}}

### Post-Plan Tasks

| Task Name     | Status                    | Enforcement            | Message     |
| ------------- | ------------------------- | ---------------------- | ----------- |
| {{TASK_NAME}} | {{passed/failed/errored}} | {{advisory/mandatory}} | {{message}} |

{{For each task with outcomes, add a sub-table:}}

#### {{TASK_NAME}} — Outcomes

| Outcome        | Description     | Status     | Severity           |
| -------------- | --------------- | ---------- | ------------------ |
| {{outcome_id}} | {{description}} | {{status}} | {{severity or --}} |

### Key Findings

{{Synthesize actionable findings from outcome body_html:

- Cost estimates with resource-level breakdown
- Policy violations with affected resource count
- Recommendations for optimization
  If no run tasks configured, note: "No run tasks configured for this workspace."
  If no run ID available, note: "Run tasks: SKIPPED (no run ID)."}}

## Quality Score

| #   | Dimension              | Score   | Issues      |
| --- | ---------------------- | ------- | ----------- |
| 1   | Module Usage           | {{X.X}} | {{summary}} |
| 2   | Security & Compliance  | {{X.X}} | {{summary}} |
| 3   | Code Quality           | {{X.X}} | {{summary}} |
| 4   | Variables & Outputs    | {{X.X}} | {{summary}} |
| 5   | Wiring & Integration   | {{X.X}} | {{summary}} |
| 6   | Constitution Alignment | {{X.X}} | {{summary}} |

**Overall Score**: {{X.X}}/10.0 — {{Level}}
**Production Readiness**: {{Ready / Not Ready}}

## Sandbox Deployment

| Field               | Value                           |
| ------------------- | ------------------------------- |
| Workspace           | {{SANDBOX_WORKSPACE}}           |
| Run URL             | {{RUN_URL}}                     |
| Plan Status         | {{PLANNED / ERRORED}}           |
| Apply Status        | {{APPLIED / ERRORED / SKIPPED}} |
| Resources Created   | {{N}}                           |
| Resources Changed   | {{N}}                           |
| Resources Destroyed | {{N}}                           |
| Cost Estimate       | {{MONTHLY_COST or N/A}}         |

{{If ERRORED, include error summary}}

## Sandbox Destroy

| Field           | Value                             |
| --------------- | --------------------------------- |
| Destroy Status  | {{DESTROYED / SKIPPED / ERRORED}} |
| Destroy Run URL | {{RUN_URL or N/A}}                |

## Overall Status

**{{PASS / FAIL}}**

{{If FAIL, list each failing category as a bullet}}
