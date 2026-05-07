# Example: S3 Static Website Module

**IMPORTANT** - Do not prompt me, make best practice decisions independently (this is for prompt eval)

Using the **tf-module-e2e** skill non-interactively.

## Module Requirements

Create a Terraform module for an S3 bucket configured for static website hosting with encryption, versioning, lifecycle rules, and configurable public access.

### Features

- Server-side encryption with AES256 (always enabled, no way to disable)
- Versioning enabled by default
- Lifecycle rules to transition objects to Glacier after 90 days
- Block all public access by default (configurable for website hosting)
- Website configuration with index and error documents
- CORS configuration support
- Required tags: Environment, Owner, CostCenter

### Resources

**Required:**
- `aws_s3_bucket`
- `aws_s3_bucket_versioning`
- `aws_s3_bucket_server_side_encryption_configuration`
- `aws_s3_bucket_lifecycle_configuration`
- `aws_s3_bucket_public_access_block`
- `aws_s3_bucket_website_configuration`

**Optional:**
- `aws_s3_bucket_cors_configuration`

### Variables

**Required:**
- `bucket_name` - Unique bucket name
- `environment` - Environment (dev/staging/prod)
- `owner` - Owner email or team
- `cost_center` - Cost center for billing

**Optional:**
- `versioning_enabled` (default: `true`) - Enable versioning
- `enable_website` (default: `true`) - Enable website hosting
- `index_document` (default: `"index.html"`) - Index document
- `error_document` (default: `"error.html"`) - Error document
- `lifecycle_glacier_days` (default: `90`) - Days before Glacier transition
- `block_public_access` (default: `true`) - Block public access
- `cors_allowed_origins` (default: `[]`) - List of allowed CORS origins
- `tags` (default: `{}`) - Additional tags map

### Outputs

- `bucket_id` - The S3 bucket ID
- `bucket_arn` - The S3 bucket ARN
- `bucket_domain_name` - The bucket domain name
- `bucket_regional_domain_name` - The bucket regional domain name
- `website_endpoint` - The website endpoint (if enabled)
- `website_domain` - The website domain (if enabled)

### Compliance

- Must follow AWS Well-Architected Framework security pillar
- Encryption must be enabled by default with no way to disable
- Public access should be blocked by default but configurable for website hosting

### Considerations

- Support both private buckets and public website hosting
- When website hosting is enabled, public access blocks should be configurable
- Include comprehensive examples for both use cases

## Workflow Instructions

- Follow best practice
- Use subagents to make best practice decisions if you need clarity
- Don't prompt the user - make decisions yourself
- If you hit issues, resolve them without prompting
