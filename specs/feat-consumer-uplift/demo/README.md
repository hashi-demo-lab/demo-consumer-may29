# Consumer Module Uplift — Demo Harness

End-to-end demo of the consumer module uplift pipeline. Creates a TFC workspace, deploys consumer code, publishes a new module version, and triggers Dependabot-style PRs that exercise the deterministic upgrade pipeline with `@claude` remediation.

## Architecture

```
┌─────────────────────┐   PR merge + CI     ┌──────────────────────────┐
│ Source Module Repo   │ ──────────────────► │  HCP Terraform PMR      │
│ (s3-bucket)          │   pr_merge.yml      │  s3-bucket/aws @ X.Y.Z  │
└─────────────────────┘   publishes via API  └──────────────────────────┘
                                                        │
                                                        ▼
┌─────────────────────┐   PR triggers      ┌──────────────────────────┐
│ Demo Consumer Repo   │ ◄──────────────── │  trigger-bump.sh creates │
│ (cloned template)    │   workflow         │  dependabot-style PR     │
└─────────────────────┘                    └──────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────────────┐
│  terraform-consumer-uplift.yml                                    │
│  Classify → Validate → Risk Assessment → Decision (merge/review/block)│
└───────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- `gh` CLI authenticated to the target GitHub host
- `TFE_TOKEN` environment variable set (org-level or team token)
- Claude Code OAuth token (from `~/.claude/.credentials.json` → `accessToken` field)
- AWS credentials configured in the TFC project (variable set) for the sandbox workspace
- Demo repo created via `create-demo-repos.zsh` and cloned locally

## End-to-End Walkthrough

> **IMPORTANT**: All scripts must be run from the **demo repo clone**, not the template repo.
> The template repo (`terraform-agentic-workflows`) is only for development. Scripts use
> `git rev-parse --show-toplevel` to find the repo root and push to its `origin`.

### Step 1: Create a demo repo from the template

```bash
# From the template repo root
./create-demo-repos.zsh -t <template-number> -c 1

# Clone the demo repo and cd into it
cd ~/Documents/repos/<demo-repo-name>
```

### Step 2: Configure

```bash
# Copy the example config
cp specs/feat-consumer-uplift/demo/demo.env.example specs/feat-consumer-uplift/demo/demo.env

# Edit demo.env — key settings:
#   BASE_BRANCH        → "feat/consumer-module-uplift" (current dev branch)
#                         Change to "main" once the workflow is merged
#   TFE_ORG            → your TFC org
#   TFE_PROJECT        → project with AWS credentials (variable set)
#   MODULE_SOURCE      → full PMR module source path
#   MODULE_SOURCE_REPO → GitHub repo backing the PMR module
#   DEMO_SCENARIO      → patch | minor | breaking | no-op
```

### Step 3: Setup (workspace + consumer code)

```bash
bash specs/feat-consumer-uplift/demo/setup.sh
```

This creates:
- A TFC workspace (CLI-driven) in your sandbox project
- Consumer Terraform code (`.tf` files) committed to the base branch
- GitHub labels for the pipeline (risk levels, decisions)

If `terraform init/plan` fails (e.g. no AWS creds in workspace yet), that's OK — the workflow will handle it. Add `SKIP_PLAN=true` to skip.

### Step 4: Verify `.mcp.json` in demo repo

> **Note**: `setup.sh` now automatically sets GitHub secrets (`TFE_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `TFE_TOKEN_DEPENDABOT`) and configures the repo default branch. If any fail (e.g. permissions), the script prints manual fallback commands.
>
> `CLAUDE_CODE_OAUTH_TOKEN` is read from `~/.claude/.credentials.json` → `accessToken` field. It uses your Claude Pro/Team subscription rather than API credits.

The demo repo's `.mcp.json` must use **npx-based** MCP servers (not Docker) for GitHub Actions compatibility:

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

`claude-code-action` hardcodes `enableAllProjectMcpServers: true`, so a Docker-based config will crash the action in CI where Docker isn't available.

### Step 5: Publish a new module version to the PMR

**Always run this before `trigger-bump.sh`.** The target version must exist in the PMR.

This module uses **branch-based publishing** — the source repo (`hashi-demo-lab/terraform-aws-s3-bucket`) has a `pr_merge.yml` workflow that auto-publishes to the PMR when a PR is merged to `main` with a semver label.

```bash
# Patch bump (default): e.g. 5.8.5 → 5.8.6
bash specs/feat-consumer-uplift/demo/publish-module-version.sh

# Minor bump: e.g. 5.8.5 → 5.9.0
bash specs/feat-consumer-uplift/demo/publish-module-version.sh --bump minor

# Major bump: e.g. 5.8.5 → 6.0.0
bash specs/feat-consumer-uplift/demo/publish-module-version.sh --bump major
```

The script:
1. Queries PMR for the current latest version
2. Calculates the next version based on bump type
3. Creates a branch + trivial commit on the source module repo
4. Opens a PR with the `semver:patch/minor/major` label
5. Waits for validation CI, then merges the PR
6. Waits for `pr_merge.yml` to publish the new version to the PMR
7. Polls until TFC ingests the version (timeout: 6 min)
8. Updates `MODULE_TARGET_VERSION` and `MODULE_CURRENT_VERSION` in local `demo.env`

### Step 6: Trigger the demo

```bash
# Uses default scenario from demo.env
bash specs/feat-consumer-uplift/demo/trigger-bump.sh

# Or pick a specific scenario
bash specs/feat-consumer-uplift/demo/trigger-bump.sh --scenario minor
```

This creates a PR with a `dependabot/terraform/` branch prefix, which triggers the consumer uplift workflow.

The version replacement uses a flexible regex that matches any existing constraint format (`"5.8.5"`, `"~> 5.8.5"`, `">= 5.8.5"`, etc.), so it works regardless of what previous runs left on the base branch.

### Step 7: Watch the pipeline

Open the **Actions** tab in the GitHub repo to watch:
1. **Classify** — detects semver type from the git diff
2. **Validate** — runs `terraform fmt/init/validate/plan` against TFC workspace
3. **Risk Assessment** — deterministic matrix classifies risk from plan output (if plan shows changes)
4. **Decision** — labels, comments with risk assessment, and optionally auto-merges

### Step 8: Clean up

```bash
bash specs/feat-consumer-uplift/demo/teardown.sh
```

This destroys infrastructure, deletes the workspace, closes PRs, removes demo branches, and removes consumer `.tf` files.

## Repeating the Demo

To trigger another run **without full teardown/setup**:

```bash
# 1. Publish a new version (auto-detects current, bumps, updates demo.env)
bash specs/feat-consumer-uplift/demo/publish-module-version.sh --bump patch

# 2. Trigger (reads updated demo.env, creates PR)
bash specs/feat-consumer-uplift/demo/trigger-bump.sh --scenario patch
```

For the **major** scenario (risk:high demo), use `--bump major` to publish:

```bash
bash specs/feat-consumer-uplift/demo/publish-module-version.sh --bump major
bash specs/feat-consumer-uplift/demo/trigger-bump.sh --scenario major
```

This adds KMS encryption, a dedicated logging bucket, lifecycle rules, and new outputs — producing both adds (new resources) and changes to existing resources, which the deterministic matrix will flag as risk:high for a major version bump.

This works repeatedly — each cycle publishes a new PMR version and creates a fresh PR. No manual `demo.env` editing needed between runs.

## Demo Scenarios

| Scenario | What Changes | Pipeline Path | Best For Showing |
|----------|-------------|---------------|-----------------|
| `patch` | Version constraint + DemoRun tag | Classify → Validate (exit 2) → Risk Assessment → Decision | Adds-only path (risk:low, needs-review) |
| `minor` | Version + logging config + new output | Classify → Validate (exit 2) → Risk Assessment → Decision | Changes to existing (risk:medium, needs-review) |
| `major` | KMS encryption + logging bucket + lifecycle rules + 5 outputs | Classify → Validate (exit 2) → Risk Assessment → Decision (risk:high) | Adds + changes with major version, `@claude` remediation |
| `breaking` | Version + invalid output reference | Classify → Validate (exit 1) → Breaking label | Breaking change detection and blocking |
| `no-op` | Constraint format change only | Classify → Validate (exit 0) → PR auto-closed | No-change detection with explanation |

Run multiple scenarios (each creates a separate PR):
```bash
bash specs/feat-consumer-uplift/demo/trigger-bump.sh --scenario patch
bash specs/feat-consumer-uplift/demo/trigger-bump.sh --scenario minor
bash specs/feat-consumer-uplift/demo/trigger-bump.sh --scenario major
bash specs/feat-consumer-uplift/demo/trigger-bump.sh --scenario breaking
```

Note: For multiple scenarios, publish a new version between each if you want distinct version bumps, or they'll all reference the same target version.

## What Each Script Does

| Script | Purpose |
|--------|---------|
| `setup.sh` | Creates TFC workspace, templates consumer code, commits to base branch, creates labels |
| `publish-module-version.sh` | Drives source repo CI: creates PR → merges → publishes to PMR → updates `demo.env` |
| `trigger-bump.sh` | Creates a dependabot-style PR with scenario-specific changes → triggers pipeline |
| `teardown.sh` | Destroys infra, deletes workspace, closes PRs, cleans branches/files |

## Configuration Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `BASE_BRANCH` | (auto-detect) | Branch with workflow files. Set to `feat/consumer-module-uplift` during dev |
| `TFE_ORG` | `hashi-demos-apj` | HCP Terraform organization |
| `TFE_PROJECT` | `sandbox` | TFC project name (should have AWS creds via variable set) |
| `TFE_HOSTNAME` | `app.terraform.io` | TFC hostname |
| `TFE_WORKSPACE` | (auto from repo name) | Workspace name |
| `GITHUB_REPO` | (auto from git remote) | GitHub repo (owner/name) |
| `MODULE_NAME` | `s3-bucket` | PMR module name |
| `MODULE_SOURCE` | `app.terraform.io/hashi-demos-apj/s3-bucket/aws` | Full module source |
| `MODULE_CURRENT_VERSION` | (set by publish script) | Current version on base branch |
| `MODULE_TARGET_VERSION` | (set by publish script) | Version to bump to — must exist in PMR |
| `MODULE_SOURCE_REPO` | `hashi-demo-lab/terraform-aws-s3-bucket` | VCS repo backing the PMR module |
| `MODULE_SOURCE_BRANCH` | `master` | Default branch of the source module repo |
| `AWS_REGION` | `ap-southeast-2` | AWS region |
| `DEMO_SCENARIO` | `patch` | Default trigger scenario |

## Branch Awareness

This workflow currently lives on the `feat/consumer-module-uplift` branch. When testing:

- Set `BASE_BRANCH="feat/consumer-module-uplift"` in `demo.env`
- **Set the demo repo's default branch** to `feat/consumer-module-uplift` (required for `claude-code-action`)
- The demo repo (created from template) includes this branch
- PRs will be created against this branch, not `main`
- Once the workflow is merged to `main`, change `BASE_BRANCH` to `"main"` and reset the default branch

## Multi-Person Demo Setup

Each presenter gets their own demo repo via `create-demo-repos.zsh`:

```bash
# Creates demo01, demo02, etc. — each is a full clone with all branches
./create-demo-repos.zsh -t <template-number> -c 5

# Each presenter configures their own demo.env and runs the walkthrough
# Workspaces are isolated (named after the repo)
# TFC project-level variable sets handle AWS credentials
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Pipeline doesn't trigger | Check branch name starts with `dependabot/terraform/` and PR changes `*.tf` files |
| Classify says "No module version changes" | The version sed replacement didn't match. Verify `main.tf` on base branch — the `replace_version()` function handles any constraint format, but check the diff actually shows a version change |
| `terraform init` fails with "failed to create backend alias" | Remove `TF_WORKSPACE: ""` from workflow env block — empty string conflicts with cloud backend |
| Plan exit code always 0 | Must use `PIPESTATUS[0]` when piping terraform through `tee` — `tee` always exits 0 |
| @claude fix crashes instantly (0 cost, ~200ms) | `.mcp.json` uses Docker-based MCP server. Replace with npx-based config (see Step 6) |
| "Credit balance is too low" in @claude step | Switch from `ANTHROPIC_API_KEY` to `CLAUDE_CODE_OAUTH_TOKEN` (uses Claude subscription) |
| Risk assessment job skipped | Only runs when plan exit code is 2 (changes detected) |
| Workflow not found by claude-code-action | Default branch must have the workflow file (see Step 4) |
| Labels not created | Run `setup.sh` again or create manually via `gh label create` |
| Workspace delete fails | Resources may still exist; destroy via TFC UI first |
| `trigger-bump.sh` refuses to run | `MODULE_TARGET_VERSION` must differ from `MODULE_CURRENT_VERSION` — run `publish-module-version.sh` first |
| Module version stuck in pending | Branch-based modules need TFC to clone the repo; check VCS connection in TFC |
| Wrong base branch for PR | Verify `BASE_BRANCH` in `demo.env` matches the branch with workflow files |
| Scripts modify template repo instead of demo | You ran from the template repo. Always `cd` into the **demo repo clone** first |
| `OIDC token missing` error in AI step | Add `id-token: write` to workflow permissions |
