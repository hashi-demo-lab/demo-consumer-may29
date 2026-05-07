# AGENTS.md

<default_follow_through_policy>
- If the user's intent is clear and the next step is reversible and low-risk, proceed without asking.
- Ask permission only if the next step is:
  (a) irreversible,
  (b) has external side effects (for example sending, purchasing, deleting, or writing to production), or
  (c) requires missing sensitive information or a choice that would materially change the outcome.
- If proceeding, briefly state what you did and what remains optional.
</default_follow_through_policy>

<instruction_priority>
- User instructions override default style, tone, formatting, and initiative preferences.
- Safety, honesty, privacy, and permission constraints do not yield.
- If a newer user instruction conflicts with an earlier one, follow the newer instruction.
- Preserve earlier instructions that do not conflict.
</instruction_priority>

<dependency_checks>
- Before taking an action, check whether prerequisite discovery, lookup, or memory retrieval steps are required.
- Do not skip prerequisite steps just because the intended final action seems obvious.
- If the task depends on the output of a prior step, resolve that dependency first.
</dependency_checks>

## Context

This repository is a **Terraform development template** using **SDD** (Spec-Driven Development, 4-phase workflow). It supports three workflows: **module authoring** (raw resources with secure defaults), **provider development** (Plugin Framework resources), and **consumer provisioning** (composing infrastructure from private registry modules). All workflows share the same 4-phase structure: Clarify, Design, Implement, Validate.


## Shell Safety

Never generate shell commands containing dangerous bash parameter expansion patterns. These trigger Copilot CLI security warnings and can enable arbitrary code execution (CVE-2026-29783):

- **Prompt expansion**: `${var@P}` — executes embedded command substitutions
- **Assignment side-effects**: `${var=value}` or `${var:=value}` — assigns during expansion
- **Indirect expansion**: `${!var}` — dereferences arbitrary variable names
- **Nested substitution**: `$(cmd)` inside `${...}` default values

Use simple `"$VAR"` quoting and explicit conditionals instead of parameter expansion tricks.

## Workflow Entry Points

| Command                  | Purpose                                                                               |
| ------------------------ | ------------------------------------------------------------------------------------- |
| `/tf-module-plan`        | Full 4-phase workflow: Clarify, Design, Implement (TDD), Validate                     |
| `/tf-module-implement`   | Implementation only — starts from an existing `design.md`                             |
| `/tf-provider-plan`      | Full 4-phase workflow for provider resources: Clarify, Design, Implement, Validate    |
| `/tf-provider-implement` | Implementation only — starts from an existing provider `design.md`                    |
| `/tf-consumer-plan`      | Full 4-phase workflow for consumer provisioning: Clarify, Design, Implement, Validate |
| `/tf-consumer-implement` | Implementation only — starts from an existing `consumer-design.md`                    |

## Constitutions

Non-negotiable rules for all code generation live in the constitutions. Read the relevant one before generating code.

- **Module constitution**: `.foundations/memory/module-constitution.md`
- **Provider constitution**: `.foundations/memory/provider-constitution.md`
- **Consumer constitution**: `.foundations/memory/consumer-constitution.md`

## Design Templates

When creating design documents, use the canonical template for the relevant workflow:

- **Module design**: `.foundations/templates/module-design-template.md`
- **Provider design**: `.foundations/templates/provider-design-template.md`
- **Consumer design**: `.foundations/templates/consumer-design-template.md`

## Gotchas

- **`disableAllHooks` also disables the statusline.** The `disableAllHooks` setting in `settings.local.json` disables both hooks **and** `statusLine` command execution. If the statusline disappears, check this setting first.

## Key Conventions

- Workflow conventions are defined in the orchestrator skills (`tf-module-plan`, `tf-module-implement`, `tf-provider-plan`, `tf-provider-implement`, `tf-consumer-plan`, `tf-consumer-implement`). Follow AGENTS.md `## Context Management` for subagent rules.
- Key scripts: `validate-env.sh` (environment checks), `post-issue-progress.sh` (GitHub updates), `checkpoint-commit.sh` (git automation) — all in `.foundations/scripts/bash/`.

## Updating AGENTS.md Files

When you discover new information that would be helpful for future development work:

- **Update existing AGENTS.md files** when you learn implementation details, debugging insights, or architectural patterns specific to that component
- **Create new AGENTS.md files** in relevant directories when working with areas that don't yet have documentation
- **Add valuable insights** such as common pitfalls, debugging techniques, dependency relationships, or implementation patterns

## Context Management

These rules apply to ALL three workflows. Replace `{workflow}` with `module`, `provider`, or `consumer` as appropriate.

1. **NEVER call TaskOutput** to read subagent results. ALL agents — including research agents — write artifacts to disk. The orchestrator verifies expected files exist after each dispatch.
2. **Verify file existence with Glob** after each agent completes — do NOT read file contents into the orchestrator.
3. **Downstream agents read their own inputs from disk.** The orchestrator passes the FEATURE path plus scope via `$ARGUMENTS`. The design agent reads research files from `specs/{FEATURE}/research-*.md` itself.
4. **Research agents: parallel foreground Task calls** (NOT `run_in_background`). Launch ALL research agents in a single message with multiple Task tool calls. Each writes findings to `specs/{FEATURE}/research-{slug}.md`. Verify files exist via Glob before launching the design agent.
5. **Minimal $ARGUMENTS**: Only pass the FEATURE path + a specific question or scope. No exceptions.

### Consumer-Specific Rules

7. **Sandbox destroy is orchestrator-controlled**: The orchestrator (not the validator) prompts the user about destroying sandbox resources after PR creation.

### Agent Output Persistence

Subagents persist output artifacts to disk. The orchestrator verifies expected files exist after each dispatch.
