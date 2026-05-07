# Validation Report: {{MODULE_NAME}}

| Field    | Value                |
| -------- | -------------------- |
| Branch   | {{BRANCH}}           |
| Date     | {{DATE}}             |
| Provider | {{PROVIDER_VERSION}} |

## terraform test

| Test File             | Result        |
| --------------------- | ------------- |
| basic.tftest.hcl      | {{PASS/FAIL}} |
| complete.tftest.hcl   | {{PASS/FAIL}} |
| edge_cases.tftest.hcl | {{PASS/FAIL}} |
| validation.tftest.hcl | {{PASS/FAIL}} |

**Summary**: {{PASSED}}/{{TOTAL}} passed

## terraform validate

**Result**: {{CLEAN / ERRORS}}

{{If errors, list each as a bullet: file:line — message}}

## terraform fmt -check

**Result**: {{FORMATTED / NEEDS FORMATTING}}

{{If unformatted, list files as bullets}}

## tflint

**Result**: {{CLEAN / FINDINGS}}

{{If FINDINGS, list each as a bullet: file:line — rule — message}}

## pre-commit run --all-files

**Result**: {{PASS / FAIL}}

{{If FAIL, list each failing hook and file as a bullet}}

## trivy config

| Metric   | Count |
| -------- | ----- |
| Total    | {{N}} |
| Defects  | {{N}} |
| Accepted | {{N}} |

### Defects (block release)

| AVD-ID     | Severity                     | File:Line     | Description     |
| ---------- | ---------------------------- | ------------- | --------------- |
| {{AVD-ID}} | {{CRITICAL/HIGH/MEDIUM/LOW}} | {{file:line}} | {{description}} |

### Accepted Risks (do not block release)

| AVD-ID     | Severity     | File:Line     | Description     | Justification (design.md ref)            |
| ---------- | ------------ | ------------- | --------------- | ---------------------------------------- |
| {{AVD-ID}} | {{severity}} | {{file:line}} | {{description}} | {{Section and rationale from design.md}} |

{{Accepted risks are design decisions documented in design.md Section 2 or 4.
They are tracked but do not block release.}}

## Security Checklist

Controls from design.md Section 4. Each control is pass or fail.

| #   | Control          | Result        |
| --- | ---------------- | ------------- |
| 1   | {{CONTROL_NAME}} | {{PASS/FAIL}} |
| 2   | {{CONTROL_NAME}} | {{PASS/FAIL}} |
| ... | ...              | ...           |

## Overall Status

**{{PASS / FAIL}}**

{{If FAIL, list each failing category as a bullet}}