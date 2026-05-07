---
# =============================================================================
# AGENT DEFINITION TEMPLATE
# =============================================================================
#
# Place in: agents/{agent-name}.md → synced to .claude/agents/ in downstream repos
#
# Filename Rules (enforced by hooks/validate_agents.py):
#   - Kebab-case: ^[a-z][a-z0-9-]+\.md$
#   - Filename = agent identity: security-auditor.md → "security-auditor"
#   - One agent per file, single responsibility
#   - Avoid generic names: helper.md, assistant.md, default.md
#
# YAML Frontmatter (optional per guide — filename alone is sufficient for discovery):
#   Standard fields:
#   - name:        kebab-case, must match filename (max 64 chars)
#   - description: WHAT it does + WHEN to use it (max 1024 chars)
#   Optional non-standard fields:
#   - model:       opus | sonnet | haiku (match to task complexity)
#   - color:       UI identifier (blue, purple, magenta, orange, green, red)
#   - skills:      reference skill names for progressive disclosure (Level 3 detail)
#   - tools:       list ONLY tools the agent actually needs — do not over-provision
#
# Validation:
#   python3 hooks/validate_agents.py
#
# Reference:
#   reference/agent-authoring-guide.md
#   Source: https://code.claude.com/docs/en/sub-agents
#
# =============================================================================

name: [agent-name]
description: >
  [WHAT: One sentence — specific transformation this agent performs on inputs].
  [WHEN: One sentence — trigger conditions, e.g., "Use after plan creation" or "Use before deployment"].
model: [opus|sonnet|haiku]
color: [blue|purple|magenta|orange|green|red]
skills:
  - [skill-name]
tools:
  - [Only tools the agent needs — see common sets below]
  # --- Common tool sets ---
  # Read-only analysis:    Read, Grep, Glob
  # Read + write reports:  Read, Write, Grep, Glob
  # Full execution:        Bash, Read, Write, Edit, Glob, Grep
  # MCP tools:             mcp__[server]__[tool_name]
---

# [Agent Title]

<!--
1-2 sentences: what input → what transformation → what output.
Be specific: "Evaluate Terraform modules for AWS security vulnerabilities"
   NOT vague: "Help with Terraform"
-->

[WHAT this agent does, specifically. State the input it expects and the output it produces.]

## Instructions

<!--
Step-by-step guidance for how the agent should approach tasks.
Structure as numbered steps with **bold phase names**.
Each step = a clear, actionable phase with explicit inputs/outputs.
Include data dependencies between steps.
For complex phases, use sub-headings (### 1. Phase Name) — see sdd-analyze.md.

Common patterns (from Anthropic guide):
  - Sequential workflow: steps depend on prior outputs
  - Iterative refinement: generate → validate → fix → re-validate
  - Context-aware routing: decision tree based on input characteristics
-->

1. **[Load/Initialize]**: [Read input artifacts, load context/prerequisites, validate inputs exist]
2. **[Process/Analyze]**: [Core work — apply domain expertise, use skills/tools, generate findings]
3. **[Generate/Report]**: [Produce output in the specified format at the specified location]
4. **[Validate]**: [Verify output completeness — all findings cited, format correct, constraints met]

## Output

<!--
Define WHERE the agent writes results and in WHAT format.
If output uses a template, reference it. If the output has a structured format
(tables, sections, severity levels), define the schema here.
-->

- **Location**: `[path/to/output.md]`
- **Format**: [Description of output structure]

<!--
If the output has a specific record structure, define it inline:

Each finding MUST use this structure:

### [Title]

**Severity**: [Critical|High|Medium|Low]
**Finding**: [Description with file:line reference]
**Recommendation**: [Actionable fix]
**Source**: [Citation URL or reference]
-->

## Constraints

<!--
Consolidate ALL rules here — do not scatter rules across sections.

Order by importance (most critical first). Keep each constraint:
  - Specific and enforceable (not vague aspirations)
  - Scoped: what this agent does NOT cover (other agents handle that)

Categories to consider:
  - Scope boundaries (what's in/out)
  - Read/write permissions (which artifacts are read-only)
  - Evidence requirements (cite file:line, provide sources)
  - Output limits (max findings, aggregation rules)
  - Quality gates (what makes output "not ready")
  - Non-negotiable rules (constitution/compliance = CRITICAL)
-->

- [SCOPE: What this agent covers and explicitly does NOT cover]
- [PERMISSIONS: Read-only on input artifacts — only write to output location]
- [EVIDENCE: Every finding must include file:line reference and source citation]
- [QUALITY: Specific quality bar — e.g., "actionable recommendations with before/after code"]
- [LIMITS: Max findings, aggregation for overflow, graceful handling of zero issues]

## Examples

<!--
Show concrete GOOD and BAD examples of agent output.
  - Good: exact format expected, with real-world detail (file:line, citations, severity)
  - Bad: common mistakes — missing evidence, vague findings, no actionable fix
Match the format to your Output section above.
-->

**Good**:
```
[Example of correct output — include file:line references, severity ratings,
citations, and actionable recommendations as appropriate for this agent]
```

**Bad** ([brief reason — e.g., "missing citations and evidence"]):
```
[Example of incorrect output — show what to avoid]
```

## Context

$ARGUMENTS
