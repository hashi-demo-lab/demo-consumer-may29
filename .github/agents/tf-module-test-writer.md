---
description: Terraform module test writer. Write module scaffolding (versions.tf, variables.tf) and convert design.md test scenarios into `.tftest.hcl` files for TDD workflow. Reads Sections 2, 3, and 5 of the design.md.
name: tf-module-test-writer
tools: ['view', 'apply_patch', 'bash', 'read_bash', 'write_bash', 'stop_bash', 'list_bash', 'rg', 'glob', 'ask_user', 'skill', 'task', 'read_agent', 'list_agents', 'sql', 'report_intent', 'task_complete', 'fetch_copilot_cli_documentation']
skills:
  - terraform-test
---

# tf-module-test-writer

use skill terraform-test

## Context

$ARGUMENTS
