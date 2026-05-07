# Skills Authoring Guide

Comprehensive reference for writing Claude Code skills, based on two primary sources:

- [The Complete Guide to Building Skills for Claude](https://resources.anthropic.com/hubfs/The-Complete-Guide-to-Building-Skill-for-Claude.pdf) (Anthropic PDF, January 2026) — design principles, patterns, and best practices
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills) — technical reference for Claude Code-specific features

Sections sourced from the Claude Code docs are marked with **(Claude Code)**.

---

## 1. Overview

A **skill** is a set of instructions — packaged as a simple folder — that teaches Claude how to handle specific tasks or workflows. Instead of re-explaining your preferences, processes, and domain expertise in every conversation, skills let you teach Claude once and benefit every time.

Skills work identically across Claude.ai, Claude Code, and the API. Create a skill once and it works across all surfaces without modification, provided the environment supports any dependencies the skill requires.

Claude can load multiple skills simultaneously. Your skill should work well alongside others, not assume it's the only capability available.

### Common Use Case Categories

| Category | Used for | Example |
|----------|----------|---------|
| **Document & Asset Creation** | Creating consistent, high-quality output (docs, presentations, designs, code) | `frontend-design` skill |
| **Workflow Automation** | Multi-step processes that benefit from consistent methodology | `skill-creator` skill |
| **MCP Enhancement** | Workflow guidance layered on top of MCP tool access | `sentry-code-review` skill |

---

## 2. Core Design Principles

### The Context Window Is a Public Good

Skills share the context window with everything else Claude needs: system prompt, conversation history, other skills' metadata, and the actual user request. Only include what the model doesn't already know. Challenge each line: *does this justify its tokens?*

*(Source: [Anthropic best-practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices))*

### Progressive Disclosure

Skills use a three-level system to minimize token usage while maintaining specialized expertise:

1. **YAML frontmatter** (Level 1) — always loaded in Claude's system prompt. Provides just enough information for Claude to know *when* each skill should be used without loading all of it into context. Budget: ~100 tokens.
2. **SKILL.md body** (Level 2) — loaded when Claude thinks the skill is relevant to the current task. Contains the full instructions and guidance. Budget: <5,000 tokens ([AgentSkills.io](https://agentskills.io/specification)) / <5,000 words ([Anthropic PDF](https://resources.anthropic.com/hubfs/The-Complete-Guide-to-Building-Skill-for-Claude.pdf)).
3. **Linked files** (Level 3) — additional files bundled within the skill directory (`references/`, `scripts/`, `assets/`) that Claude can choose to navigate and discover only as needed.

### Design for Layers

- Put the most important instructions in SKILL.md itself
- Move detailed documentation to `references/` and link to it
- Move executable logic to `scripts/` — SKILL.md just explains when/how to call them
- Never duplicate information between layers

---

## 3. File Structure

```
your-skill-name/
├── SKILL.md              # Required — main skill file
├── scripts/              # Optional — executable code
│   ├── process_data.py
│   └── validate.sh
├── references/           # Optional — documentation loaded as needed
│   └── api-guide.md
└── assets/               # Optional — templates, fonts, icons used in output
    └── report-template.md
```

### Critical Rules

| Rule | Details |
|------|---------|
| **SKILL.md naming** | Must be exactly `SKILL.md` (case-sensitive). No variations: ~~SKILL.MD~~, ~~skill.md~~ |
| **Folder naming** | Kebab-case only: `notion-project-setup`. No spaces, no underscores, no capitals. |
| **No README.md** | Don't include `README.md` inside your skill folder. All documentation goes in `SKILL.md` or `references/`. |
| **No XML tags** | No `<` or `>` angle brackets in frontmatter (security restriction — frontmatter appears in Claude's system prompt). |
| **No reserved names** | Don't use "claude" or "anthropic" in skill names (reserved). |

---

## 4. SKILL.md Structure

Every `SKILL.md` has two parts:

```markdown
---
name: your-skill-name
description: What it does. Use when user asks to [specific phrases].
---

# Your Skill Name

## Instructions

### Step 1: [First Major Step]
Clear explanation of what happens.

### Step 2: [Next Step]
...

## Examples
Example 1: [common scenario]
User says: "Set up a new marketing campaign"
Actions:
1. Fetch existing campaigns via MCP
2. Create new campaign with provided parameters
Result: Campaign created with confirmation link

## Troubleshooting
Error: [Common error message]
Cause: [Why it happens]
Solution: [How to fix]
```

---

## 5. Frontmatter Reference

### Required Fields

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `name` | string | Max 64 chars. Kebab-case only (lowercase letters, numbers, hyphens). Must not start/end with hyphen. No consecutive hyphens (`--`). Must match folder name. No reserved words ("claude", "anthropic"). | Unique identifier for the skill |
| `description` | string | Under 1024 characters, no XML tags (`<` `>`) | Must include BOTH what it does AND when to use it (trigger conditions). Include specific tasks users might say. Mention file types if relevant. |

### Optional Fields (Anthropic Spec)

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `license` | string | — | License for open-source skills (e.g., `MIT`, `Apache-2.0`) |
| `compatibility` | string | 1–500 characters | Environment requirements: intended product, required system packages, network access needs, etc. |
| `allowed-tools` | string | Tool specification format | Restrict which tools the skill can use. Example: `"Bash(python:*) Bash(npm:*) WebFetch"` |
| `metadata` | object | Custom key-value pairs | Suggested keys: `author`, `version`, `mcp-server`, `category`, `tags`, `documentation`, `support` |

### Optional Fields (Claude Code)

These fields are Claude Code extensions to the [Agent Skills](https://agentskills.io) open standard:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `argument-hint` | string | — | Hint shown during autocomplete. Example: `[issue-number]` or `[filename] [format]` |
| `disable-model-invocation` | boolean | `false` | If `true`, only you can invoke the skill via `/name`. Claude will never auto-select it. Use for destructive/expensive operations. |
| `user-invocable` | boolean | `true` | If `false`, hides from the `/` menu. Only Claude can invoke it. Use for background knowledge. |
| `model` | string | — | Model to use when this skill is active. |
| `context` | string | — | Set to `fork` to run in a forked subagent context (isolated from conversation history). |
| `agent` | string | — | Which subagent type to use when `context: fork` is set. Options: `Explore`, `Plan`, `general-purpose`, or a custom agent name. |
| `hooks` | object | — | Hooks scoped to this skill's lifecycle. |

### Full Example

```yaml
---
name: my-skill
description: What it does and when to use it. Include specific trigger phrases.
license: MIT
allowed-tools: "Bash(python:*) Bash(npm:*) WebFetch"
disable-model-invocation: true
argument-hint: "[project-name] [environment]"
metadata:
  author: Company Name
  version: 1.0.0
  mcp-server: server-name
  category: productivity
  tags: [project-management, automation]
---
```

---

## 6. Writing Effective Descriptions

The `description` field is how Claude decides whether to load your skill. Get this right.

**Structure**: `[What it does]` + `[When to use it]` + `[Key capabilities]`

### Good Descriptions

```yaml
# Good — specific and actionable
description: Analyzes Figma design files and generates developer handoff
  documentation. Use when user uploads .fig files, asks for "design specs",
  "component documentation", or "design-to-code handoff".

# Good — includes trigger phrases
description: Manages Linear project workflows including sprint planning, task
  creation, and status tracking. Use when user mentions "sprint", "Linear tasks",
  "project planning", or asks to "create tickets".

# Good — clear value proposition
description: End-to-end customer onboarding workflow for PayFlow. Handles account
  creation, payment setup, and subscription management. Use when user says
  "onboard new customer", "set up subscription", or "create PayFlow account".
```

### Bad Descriptions

```yaml
# Too vague — won't trigger reliably
description: Helps with projects.

# Missing triggers — Claude doesn't know WHEN to use it
description: Creates sophisticated multi-page documentation systems.

# Too technical, no user triggers
description: Implements the Project entity model with hierarchical relationships.
```

---

## 7. String Substitutions (Claude Code)

Skills support string substitution for dynamic values in the skill content:

| Variable | Description |
|----------|-------------|
| `$ARGUMENTS` | All arguments passed when invoking the skill. If not present in content, arguments are appended as `ARGUMENTS: <value>`. |
| `$ARGUMENTS[N]` | Access a specific argument by 0-based index (e.g., `$ARGUMENTS[0]` for the first). |
| `$N` | Shorthand for `$ARGUMENTS[N]` (e.g., `$0` for first, `$1` for second). |
| `${CLAUDE_SESSION_ID}` | Current session ID. Useful for logging, session-specific files, or correlation. |
| `` !`command` `` | Runs a shell command *before* the skill content is sent to Claude. Output replaces the placeholder. This is preprocessing, not something Claude executes. |

### Examples

**Positional arguments:**
```yaml
---
name: migrate-component
description: Migrate a component from one framework to another
---

Migrate the $0 component from $1 to $2.
Preserve all existing behavior and tests.
```

Running `/migrate-component SearchBar React Vue` replaces `$0` with `SearchBar`, `$1` with `React`, `$2` with `Vue`.

**Dynamic context injection:**
```yaml
---
name: pr-summary
description: Summarize changes in a pull request
context: fork
agent: Explore
---

## Pull request context
- PR diff: !`gh pr diff`
- PR comments: !`gh pr view --comments`
- Changed files: !`gh pr diff --name-only`

## Your task
Summarize this pull request...
```

Each `` !`command` `` executes immediately, and Claude receives the fully-rendered prompt with actual data.

---

## 8. Invocation Control (Claude Code)

By default, both you and Claude can invoke any skill. Two frontmatter fields restrict this:

| Frontmatter | You can invoke | Claude can invoke | When loaded into context |
|:--|:-:|:-:|:--|
| (default) | Yes | Yes | Description always in context, full skill loads when invoked |
| `disable-model-invocation: true` | Yes | No | Description not in context, full skill loads when you invoke |
| `user-invocable: false` | No | Yes | Description always in context, full skill loads when invoked |

### Guidance

- **Default** — most skills. Available everywhere.
- **`disable-model-invocation: true`** — for workflows with side effects you want to control timing on: `/deploy`, `/commit`, `/send-slack-message`. You don't want Claude deciding to deploy because your code looks ready.
- **`user-invocable: false`** — for background knowledge that isn't actionable as a command. A `legacy-system-context` skill explains how an old system works — Claude should know it when relevant, but `/legacy-system-context` isn't a meaningful user action.

---

## 9. Writing Effective Instructions

### Best Practices

**Be specific and actionable:**

```markdown
# Good
Run `python scripts/validate.py --input {filename}` to check data format.
If validation fails, common issues include:
- Missing required fields (add them to the CSV)
- Invalid date formats (use YYYY-MM-DD)

# Bad
Validate the data before proceeding.
```

**Reference bundled resources clearly:**

```markdown
Before writing queries, consult `references/api-patterns.md` for:
- Rate limiting guidance
- Pagination patterns
- Error codes and handling
```

**Include error handling:**

```markdown
## Common Issues
### MCP Connection Failed
If you see "Connection refused":
1. Verify MCP server is running: Check Settings > Extensions
2. Confirm API key is valid
3. Try reconnecting: Settings > Extensions > [Your Service] > Reconnect
```

**For critical validations**, consider bundling a script that performs checks programmatically rather than relying on language instructions. Code is deterministic; language interpretation isn't.

### Degrees of Freedom

Match the specificity of your instructions to the fragility of the task:

| Freedom Level | Format | When to Use |
|---------------|--------|-------------|
| **HIGH** | Text instructions | Multiple valid approaches; context-dependent decisions |
| **MEDIUM** | Pseudocode / patterns | Preferred approach exists but some variation is OK |
| **LOW** | Exact scripts | Fragile operations where consistency is critical |

Think of Claude exploring a path: a narrow bridge with cliffs needs specific guardrails (low freedom), while an open field allows many valid routes (high freedom). Default to high freedom and only constrain further when the task demands it.

*(Source: [Anthropic best-practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices))*

---

## 10. Common Patterns

> **Note:** These are **workflow-type** patterns — they describe how a skill orchestrates tasks at runtime. For **content-type** patterns (how to structure the SKILL.md body itself — Knowledge, Procedural, or Reference), see the [skill definition template](skill-definition-template.md). The two taxonomies are complementary: choose a body structure from the template and a workflow pattern from here.

### Pattern 1: Sequential Workflow Orchestration

**Use when**: Users need multi-step processes in a specific order.

```markdown
## Workflow: Onboard New Customer
### Step 1: Create Account
Call MCP tool: `create_customer`
Parameters: name, email, company

### Step 2: Setup Payment
Call MCP tool: `setup_payment_method`
Wait for: payment method verification

### Step 3: Create Subscription
Call MCP tool: `create_subscription`
Parameters: plan_id, customer_id (from Step 1)

### Step 4: Send Welcome Email
Call MCP tool: `send_email`
Template: welcome_email_template
```

Key techniques: explicit step ordering, dependencies between steps, validation at each stage, rollback instructions for failures.

### Pattern 2: Multi-MCP Coordination

**Use when**: Workflows span multiple services.

Example: Design-to-development handoff that coordinates Figma MCP → Drive MCP → Linear MCP → Slack MCP in sequence, passing data between phases.

Key techniques: clear phase separation, data passing between MCPs, validation before moving to next phase, centralized error handling.

### Pattern 3: Iterative Refinement

**Use when**: Output quality improves with iteration.

```markdown
## Iterative Report Creation
### Initial Draft
1. Fetch data via MCP
2. Generate first draft report
3. Save to temporary file

### Quality Check
1. Run validation script: `scripts/check_report.py`
2. Identify issues: missing sections, inconsistent formatting, data errors

### Refinement Loop
1. Address each identified issue
2. Regenerate affected sections
3. Re-validate
4. Repeat until quality threshold met
```

Key techniques: explicit quality criteria, iterative improvement, validation scripts, knowing when to stop.

### Pattern 4: Context-Aware Tool Selection

**Use when**: Same outcome, different tools depending on context.

Example: Smart file storage that checks file type/size and routes to cloud storage MCP, Notion/Docs MCP, GitHub MCP, or local storage based on a decision tree.

Key techniques: clear decision criteria, fallback options, transparency about choices.

### Pattern 5: Domain-Specific Intelligence

**Use when**: Your skill adds specialized knowledge beyond tool access.

Example: Payment processing with compliance — fetch transaction details, apply compliance rules (sanctions lists, jurisdiction checks, risk assessment), then process or flag for review with a full audit trail.

Key techniques: domain expertise embedded in logic, compliance before action, comprehensive documentation, clear governance.

---

## 11. Testing and Iteration

### Three Testing Areas

**1. Triggering tests** — Does the skill load at the right times?
- Should trigger on obvious tasks
- Should trigger on paraphrased requests
- Should NOT trigger on unrelated topics

**2. Functional tests** — Does the skill produce correct outputs?
- Valid outputs generated
- API calls succeed
- Error handling works
- Edge cases covered

**3. Performance comparison** — Does the skill improve results vs. baseline?
- Compare tool call count, token usage, and user corrections with vs. without the skill

### Success Metrics (Aspirational Benchmarks)

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Skill triggers on relevant queries | ~90% | Run 10–20 test queries, track auto-trigger rate |
| Workflow completes in X tool calls | Lower than baseline | Compare same task with/without skill |
| Failed API calls per workflow | 0 | Monitor MCP server logs during test runs |
| Users don't need to prompt about next steps | — | Note how often you redirect or clarify during testing |
| Consistent results across sessions | — | Run same request 3–5 times, compare outputs |

### Iteration Signals

| Signal | Meaning | Fix |
|--------|---------|-----|
| Skill doesn't load when it should | Undertriggering | Add more detail/keywords to description |
| Skill loads for irrelevant queries | Overtriggering | Add negative triggers, be more specific |
| Inconsistent results / API failures | Execution issues | Improve instructions, add error handling |

---

## 12. Anti-Patterns

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| Hardcoded paths (`/Users/me/...`) | Breaks on other machines | Use relative paths or env vars |
| Secrets in SKILL.md | Security risk | Use environment variables |
| README.md in skill dir | Not supported by skill system | Put docs in SKILL.md or `references/` |
| XML tags in frontmatter | Security restriction (frontmatter is in system prompt) | Remove all `<` `>` from frontmatter |
| "claude" or "anthropic" in name | Reserved namespace | Choose a different name |
| Vague description | Claude can't decide when to invoke | Be specific: WHAT + WHEN + trigger phrases |
| Instructions too verbose | Claude may not follow them | Keep concise, use bullet points, move detail to `references/` |
| Critical instructions buried | Claude may miss them | Put critical instructions at top, use `## Important` headers |
| Info duplication across layers | Wasted context tokens | Reference files, don't inline their content |
| Too many skills enabled | Slow responses, degraded quality | Keep focused, evaluate if >20–50 simultaneous skills |

---

## 13. Hub-Specific Conventions

This hub repo has additional conventions beyond the base Anthropic spec:

### Directory Structure
- All skills live in `skills/` at the repo root (not `.claude/skills/`)
- The sync engine copies `skills/` → `.claude/skills/` in downstream repos
- Skill directory names become the skill identifiers — choose names carefully

### Naming
- Skill directory name = skill `name` frontmatter field (keep them in sync)
- Use descriptive names: `terraform-plan`, `review-pr`, `scaffold-module`
- Avoid generic names: `helper`, `utils`, `tool`

### Size Limit
- SKILL.md must be under **500 lines** (enforced by pre-commit hooks)
- This aligns with the Claude Code docs tip: *"Keep SKILL.md under 500 lines. Move detailed reference material to separate files."*
- Token/word budgets from upstream sources:
  - [AgentSkills.io specification](https://agentskills.io/specification): <5,000 tokens recommended for SKILL.md body
  - [Anthropic PDF](https://resources.anthropic.com/hubfs/The-Complete-Guide-to-Building-Skill-for-Claude.pdf): <5,000 words recommended
  - Our 500-line limit is the strictest and easiest to enforce programmatically

### Sync Behavior
- Everything under `skills/<name>/` is synced (SKILL.md, scripts/, references/, assets/)
- `README.md` files are globally excluded from sync (hub-only documentation)
- Excluded skills can be configured per-profile in `sync-config/sync-config.yaml`

### Forbidden Files in Skill Directories
- `README.md` — per Anthropic spec
- `CHANGELOG.md`, `INSTALLATION_GUIDE.md`, `QUICK_REFERENCE.md` — hub policy to prevent doc sprawl

### Validation
- Pre-commit hooks enforce: SKILL.md exists, < 500 lines, valid frontmatter, kebab-case name, description present, no forbidden files, no hardcoded paths
- Run `python3 hooks/validate_skills.py` locally to check before committing

---

## 14. Quick Checklist

From Reference A of the Anthropic guide. Use this to validate your skill before committing.

### Before You Start
- [ ] Identified 2–3 concrete use cases
- [ ] Tools identified (built-in or MCP)
- [ ] Reviewed this guide and example skills
- [ ] Planned folder structure

### During Development
- [ ] Folder named in kebab-case
- [ ] `SKILL.md` file exists (exact spelling)
- [ ] YAML frontmatter has `---` delimiters
- [ ] `name` field: kebab-case, no spaces, no capitals
- [ ] `description` includes WHAT and WHEN
- [ ] No XML tags (`<` `>`) anywhere in frontmatter
- [ ] Instructions are clear and actionable
- [ ] Error handling included
- [ ] Examples provided
- [ ] References clearly linked

### Before Committing (Hub-Specific)
- [ ] SKILL.md is under 500 lines
- [ ] No `README.md` in skill directory
- [ ] No hardcoded absolute paths
- [ ] `pre-commit run --all-files` passes

---

## Resources

### Primary Sources for This Guide
- [The Complete Guide to Building Skills for Claude](https://resources.anthropic.com/hubfs/The-Complete-Guide-to-Building-Skill-for-Claude.pdf) — Anthropic PDF (design principles, patterns, best practices)
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills) — Claude Code technical reference (frontmatter fields, substitutions, invocation control, subagents)

### Additional Resources
- [anthropics/skills](https://github.com/anthropics/skills) — public example skills repository (production-ready examples)
- [Agent Skills open standard](https://agentskills.io) — cross-platform skills standard
- [Introducing Agent Skills](https://www.anthropic.com/research/agent-skills) — Anthropic blog post
