# Example: AWS Bedrock AgentCore Module

**IMPORTANT** - Do not prompt me, make best practice decisions independently (this is for prompt eval)

Using the **tf-module-e2e** skill non-interactively.

## Module Requirements

Create a Terraform module for AWS Bedrock AgentCore that provisions a fully operational AI agent runtime environment with memory, tool management, code interpreter, API gateway, and observability — all secured with least-privilege IAM and encryption at rest by default.

### Features

- Agent runtime with configurable foundation model (Claude, Titan, etc.) and instruction prompt
- Conversation memory and optional long-term memory store for agent context persistence
- Tool definitions with Lambda or API-backed action groups for agent tool use
- Code interpreter sandbox enabled by default for safe code execution
- API gateway endpoint for agent invocation with throttling and usage plans
- CloudWatch logging and X-Ray tracing enabled by default (no way to disable logging)
- KMS encryption for all data at rest (agent memory, session state, logs)
- Guardrails association for content filtering and responsible AI controls
- Required tags: Environment, Owner, CostCenter, Project

### Resources

**Required:**
- `aws_bedrockagent_agent` - Core agent definition with model and instructions
- `aws_bedrockagent_agent_alias` - Versioned alias for stable invocation endpoint
- `aws_bedrockagent_agent_action_group` - Tool/action group bindings
- `aws_bedrockagent_knowledge_base` - Knowledge base for RAG retrieval
- `aws_iam_role` - Agent execution role with scoped permissions
- `aws_iam_role_policy` - Inline policy for Bedrock model invocation and tool access
- `aws_cloudwatch_log_group` - Agent invocation and session logs
- `aws_kms_key` - Encryption key for agent data at rest

**Optional:**
- `aws_bedrockagent_agent_knowledge_base_association` - Link knowledge base to agent
- `aws_bedrockagent_data_source` - S3 data source for knowledge base ingestion
- `aws_lambda_function` - Custom tool backend for action groups
- `aws_lambda_permission` - Allow Bedrock to invoke tool Lambda
- `aws_apigatewayv2_api` - HTTP API for external agent invocation
- `aws_apigatewayv2_stage` - API stage with throttling and logging
- `aws_bedrock_guardrail` - Content filtering guardrail
- `aws_bedrock_guardrail_version` - Pinned guardrail version

### Variables

**Required:**
- `agent_name` - Name of the Bedrock agent
- `foundation_model_id` - Model identifier (e.g., `anthropic.claude-sonnet-4-20250514`)
- `agent_instruction` - System instruction prompt for the agent
- `environment` - Environment (dev/staging/prod)
- `owner` - Owner email or team
- `cost_center` - Cost center for billing

**Optional:**
- `idle_session_ttl` (default: `600`) - Session timeout in seconds
- `enable_code_interpreter` (default: `true`) - Enable code interpreter action group
- `enable_knowledge_base` (default: `false`) - Provision and attach a knowledge base
- `knowledge_base_s3_bucket_arn` (default: `""`) - S3 bucket ARN for knowledge base data source
- `knowledge_base_embedding_model` (default: `"amazon.titan-embed-text-v2:0"`) - Embedding model for knowledge base
- `action_group_definitions` (default: `[]`) - List of action group objects with name, description, Lambda ARN, and API schema
- `enable_api_gateway` (default: `false`) - Expose agent via HTTP API Gateway
- `api_throttle_rate_limit` (default: `100`) - API Gateway requests per second
- `api_throttle_burst_limit` (default: `200`) - API Gateway burst limit
- `guardrail_id` (default: `""`) - Guardrail ID to associate with agent
- `guardrail_version` (default: `"DRAFT"`) - Guardrail version
- `kms_key_arn` (default: `""`) - Existing KMS key ARN; creates new key if empty
- `log_retention_days` (default: `90`) - CloudWatch log retention in days
- `tags` (default: `{}`) - Additional tags map

### Outputs

- `agent_id` - The Bedrock agent ID
- `agent_arn` - The Bedrock agent ARN
- `agent_alias_id` - The deployed agent alias ID
- `agent_alias_arn` - The agent alias ARN for invocation
- `agent_role_arn` - The IAM execution role ARN
- `knowledge_base_id` - The knowledge base ID (if enabled)
- `api_endpoint` - The API Gateway invocation URL (if enabled)
- `kms_key_arn` - The KMS key ARN used for encryption
- `log_group_name` - The CloudWatch log group name

### Compliance

- Must follow AWS Well-Architected Framework security and operational excellence pillars
- All data at rest must be encrypted with KMS (no way to disable)
- CloudWatch logging must be enabled by default with no way to disable
- Agent execution role must follow least-privilege (scoped to specific model and resources)
- Guardrails should be strongly encouraged for production workloads
- Session data must respect configured TTL and not persist beyond expiry

### Considerations

- Support both simple single-tool agents and complex multi-tool agents with knowledge bases
- Action group definitions should accept either Lambda ARNs or inline OpenAPI schemas
- When knowledge base is enabled, manage the full lifecycle (knowledge base, data source, association)
- API Gateway is optional to support both direct SDK invocation and HTTP-based integration patterns
- Agent alias provides a stable endpoint; updates to the agent should create new versions behind the alias
- Code interpreter should be enabled by default but configurable for environments where sandboxed execution is not permitted
- Module should be composable: consumers may bring their own Lambda functions, KMS keys, or guardrails

## Workflow Instructions

- Follow best practice
- Use subagents to make best practice decisions if you need clarity
- Don't prompt the user - make decisions yourself
- If you hit issues, resolve them without prompting
