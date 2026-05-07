# TFLint configuration for Terraform best practices
# Constitution Reference: Section 5.1 (Code Quality)
#
# Documentation: https://github.com/terraform-linters/tflint

config {
  # Enable module inspection (v0.54.0+)
  # Options: "all" (inspect all modules), "local" (local only), "none" (disabled)
  call_module_type = "all"

  # Force check even when no issues found
  force = false

  # Disable color output in CI environments
  disabled_by_default = false
}

# Enable AWS plugin for AWS-specific rules
plugin "aws" {
  enabled = true
  version = "0.46.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Enable Azure plugin for Azure-specific rules
plugin "azurerm" {
  enabled = true
  version = "0.31.1"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

plugin "terraform" {
  enabled = true
  version = "0.14.1"
  source  = "github.com/terraform-linters/tflint-ruleset-terraform"
}

# Terraform naming conventions
rule "terraform_naming_convention" {
  enabled = true

  variable {
    format = "snake_case"
  }

  locals {
    format = "snake_case"
  }

  output {
    format = "snake_case"
  }

  resource {
    format = "snake_case"
  }

  module {
    format = "snake_case"
  }

  data {
    format = "snake_case"
  }
}

# Require variable descriptions
rule "terraform_documented_variables" {
  enabled = true
}

# Require output descriptions
rule "terraform_documented_outputs" {
  enabled = true
}

# Check for unused declarations
rule "terraform_unused_declarations" {
  enabled = false
}

# Deprecated syntax checks
rule "terraform_deprecated_index" {
  enabled = true
}

rule "terraform_deprecated_interpolation" {
  enabled = true
}

# Type constraints
rule "terraform_typed_variables" {
  enabled = true
}

# Standard module structure
rule "terraform_standard_module_structure" {
  enabled = true
}

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

# Enforce pinned module sources with full semantic versioning
rule "terraform_module_pinned_source" {
  enabled = true
  style   = "semver"
}

# Enforce # comment syntax over // (HashiCorp convention)
rule "terraform_comment_syntax" {
  enabled = true
}

# Catch == [] anti-pattern (use length() instead)
rule "terraform_empty_list_equality" {
  enabled = true
}

# Warn against terraform.workspace in remote backend configs
rule "terraform_workspace_remote" {
  enabled = true
}

# Disallow deprecated lookup() with only 2 args (use map[key] instead)
rule "terraform_deprecated_lookup" {
  enabled = true
}

# Enforce valid root object in .tf.json files
rule "terraform_json_syntax" {
  enabled = true
}

# Catch duplicate keys in map literals
rule "terraform_map_duplicate_keys" {
  enabled = true
}

# Require shallow cloning for pinned git module sources
rule "terraform_module_shallow_clone" {
  enabled = true
}

# Ensure registry modules specify a version
rule "terraform_module_version" {
  enabled = true
}

# Flag unused required_providers entries
rule "terraform_unused_required_providers" {
  enabled = true
}

# AWS-specific rules
rule "aws_resource_missing_tags" {
  enabled = true
  tags = ["Environment", "Application", "ManagedBy"]
}
