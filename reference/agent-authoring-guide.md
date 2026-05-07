# Agent Authoring Guide

Reference for writing Claude Code agent definition files in this hub.
source: https://code.claude.com/docs/en/sub-agents

---

## Overview

An **agent** is a single Markdown file that defines a specialized persona or workflow for Claude Code. Agents are simpler than skills — they're just `.md` files placed in the `agents/` directory.

When synced to downstream repos, agents land in `.claude/agents/` where Claude discovers and uses them.

---

## File Structure

```
agents/
├── README.md              # Hub-only index (not synced)
├── plan-reviewer.md       # One agent per file
├── terraform-expert.md
└── security-auditor.md
```

### Rules

| Rule                      | Details                                                     |
| ------------------------- | ----------------------------------------------------------- |
| **One file per agent**    | Each `.md` file defines exactly one agent                   |
| **Filename = agent name** | `terraform-expert.md` → agent named "terraform-expert"      |
| **Kebab-case filenames**  | `^[a-z][a-z0-9-]+\.md$` — lowercase, hyphens, ends in `.md` |
| **Non-empty**             | File must have content (instructions for Claude)            |
| **Single responsibility** | One agent = one specialized role or workflow                |

---

## Optional YAML Frontmatter

Agent files can optionally include YAML frontmatter for metadata. The filename alone is sufficient for discovery — use frontmatter when you want to provide a richer description or control agent behavior.

### Standard Fields

| Field           | Required | Description                                                        |
| --------------- | -------- | ------------------------------------------------------------------ |
| **name**        | No       | Kebab-case, must match filename (max 64 chars)                     |
| **description** | No       | What the agent does + when to use it (max 1024 chars)              |

### Optional Fields

| Field      | Description                                                                           |
| ---------- | ------------------------------------------------------------------------------------- |
| **model**  | `opus`, `sonnet`, or `haiku` — match to task complexity                               |
| **color**  | UI identifier (`blue`, `purple`, `magenta`, `orange`, `green`, `red`)                 |
| **skills** | List of skill references for progressive disclosure (omit or leave empty if none)      |
| **tools**  | List of tools the agent needs (`Read`, `Write`, `Edit`, `Bash`, `Glob`, `Grep`, etc.) |

### Example

```markdown
---
name: "terraform-expert"
description: "Specialized in Terraform/OpenTofu IaC reviews and planning"
model: opus
color: blue
skills:
  - terraform-style-guide
tools:
  - Read
  - Grep
  - Glob
---

# Terraform Expert

You are a Terraform infrastructure specialist...
```

---

## Writing Effective Agents

### Structure

A typical agent file follows this pattern:

```markdown
# Agent Name

Brief description of what this agent does — state the input it expects and the output it produces.

## Instructions

Step-by-step guidance for how the agent should approach tasks.

## Output

Where results are written and in what format.

## Constraints

Boundaries, limitations, or things the agent should avoid.

## Examples

Concrete good and bad output examples.

## Context

$ARGUMENTS
```

The core sections are **Instructions** and **Constraints**. The remaining sections (**Output**, **Examples**, **Context**) are recommended — see `reference/AGENT-DEFINITION-TEMPLATE.md` for the full template with inline guidance. The opening paragraph serves as the agent's identity — keep it specific and action-oriented (e.g., "Evaluate Terraform modules for AWS security vulnerabilities").

### Tips

- **Be specific** — "You are a Terraform module reviewer who checks for Azure Verified Module compliance" is better than "You help with Terraform"
- **Include examples** — show the agent what good output looks like
- **Define scope** — clarify what the agent should and shouldn't do
- **Reference tools** — tell the agent which tools to prefer (Read, Grep, Bash, etc.)

---

## Hub-Specific Conventions

### Naming

- Filename must match the agent's identity: `security-auditor.md` for a security review agent
- Avoid generic names: `helper.md`, `assistant.md`, `default.md`

### Sync Behavior

- All `.md` files in `agents/` are synced (except `README.md`, which is globally excluded)
- Excluded agents can be configured per-profile in `sync-config/sync-config.yaml`

### Validation

- Pre-commit hooks enforce: non-empty content, kebab-case filename
- Run `python3 hooks/validate_agents.py` locally to check before committing
