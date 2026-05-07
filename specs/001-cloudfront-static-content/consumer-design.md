# Consumer Design: cloudfront-static-content

**Branch**: feat/001-cloudfront-static-content
**Date**: 2026-05-07
**Status**: Draft
**Provider**: aws ~> 6.5
**Terraform**: >= 1.14.0 (workspace pinned to 1.14.8)
**HCP Terraform Org**: hashi-demos-apj

---

## Table of Contents

1. [Purpose & Requirements](#1-purpose--requirements)
2. [Module Selection & Architecture](#2-module-selection--architecture)
3. [Module Wiring](#3-module-wiring)
4. [Security Controls](#4-security-controls)
5. [Implementation Checklist](#5-implementation-checklist)
6. [Open Questions](#6-open-questions)

---

## 1. Purpose & Requirements

This deployment provisions a CloudFront-fronted static content delivery stack for a sandbox/development tier. It composes a private S3 origin bucket in `ap-southeast-2` with a global CloudFront distribution that fronts that bucket via Origin Access Control (OAC), plus CloudWatch metric alarms that monitor the distribution's HTTP error rates. The stack is consumed by application teams who need a low-cost, secure static-asset hosting platform (HTML / JS / CSS / images) for demos and integration testing — end users access content via the CloudFront `*.cloudfront.net` domain over HTTPS.

**Scope boundary**: Out of scope: custom domains / Route 53 records / ACM certificates, WAFv2 protection, CloudFront access logging, SNS topics or notification routing for alarms, multi-environment promotion, content seeding / object uploads, IAM users for content publishers, CI/CD pipelines for asset deploys.

### Requirements

**Functional requirements** — what the deployment must provision:

- A private S3 bucket in `ap-southeast-2` storing static content, not directly reachable from the public internet
- A global CloudFront distribution that serves content from the S3 bucket as its sole origin
- A trust path between CloudFront and S3 such that ONLY the distribution can read bucket objects (origin access locked down at the bucket policy layer)
- HTTPS-only viewer access — any HTTP viewer request must be redirected to HTTPS
- A CloudWatch alarm that fires when the distribution's `5xxErrorRate` exceeds 5% (origin / CloudFront errors)
- A CloudWatch alarm that fires when the distribution's `4xxErrorRate` exceeds 25% (client / not-found errors; sandbox-friendly threshold)
- Stable outputs surfacing bucket name, bucket ARN, distribution ID, distribution domain name, and alarm ARNs for downstream consumption / smoke testing

**Non-functional requirements** — constraints on the design:

- Compose exclusively from the `hashi-demos-apj` private Terraform registry (constitution §1.1) — no public registry sources, no raw infrastructure resources beyond the glue exceptions
- Honour module secure defaults (constitution §1.2) — encryption, public access block, TLS minimum version
- Cost-optimised for sandbox: SSE-S3 (not KMS), no WAF, no access logs, default CloudFront viewer certificate (`*.cloudfront.net`)
- Authentication via HCP Terraform OIDC dynamic credentials (constitution §3.1) — no static AWS keys
- Workspace `sandbox_consumer_cloudfront-demo-consumer-may29` in the `sandbox` project, remote execution, `auto_apply = true`
- All resources tagged via provider `default_tags` with `ManagedBy`, `Environment`, `Project`, `Owner` (constitution §3.3)
- CloudFront and its alarms must be managed via the `us-east-1` provider alias because CloudFront's control-plane and `AWS/CloudFront` CloudWatch metrics live globally in `us-east-1`
- Cross-region wiring (S3 in `ap-southeast-2`, CloudFront in `us-east-1`) must avoid the S3 `307 TemporaryRedirect` first-hit cache miss

---

## 2. Module Selection & Architecture

### Architectural Decisions

**OAC over OAI for origin access**: Use CloudFront Origin Access Control (the v5 cloudfront module's default `origin_access_control` map with the built-in `s3` entry) to authorise distribution-to-bucket reads.
*Rationale*: AWS recommends OAC over the legacy OAI since 2022 (research-module-wiring.md §Rationale#2). OAC supports SSE-KMS-encrypted origins, uses the `cloudfront.amazonaws.com` service principal with an `AWS:SourceArn` condition for finer-grained authorisation, and is the natively-wired default in the private cloudfront v5 module.
*Rejected*: Legacy OAI (single `iam_arn` in bucket policy `Principal.AWS`) — research-private-modules.md notes it as legacy, the v5/v6 modules favour OAC, and OAC is the pattern documented in the private module's README.

**Bucket region `ap-southeast-2`, distribution global via `us-east-1` provider alias**: Two AWS provider configurations — default in `ap-southeast-2`, alias `us_east_1` for global services.
*Rationale*: Requirements pin the bucket to `ap-southeast-2` (data-residency / regional alignment). CloudFront is global but its control-plane API lives at `us-east-1`, and `AWS/CloudFront` CloudWatch metrics are published only to `us-east-1` — alarms created elsewhere never fire (research-module-wiring.md §Rationale#5; research-private-modules.md §Provider compatibility note).
*Rejected*: Single provider in `us-east-1` (forces bucket out of `ap-southeast-2`, violates regional requirement). Single provider in `ap-southeast-2` (alarms would silently never fire).

**Origin domain via `s3_bucket_bucket_regional_domain_name`**: Wire CloudFront `origin.domain_name` from the bucket's region-specific endpoint, never the legacy global form.
*Rationale*: The s3-bucket module's own output description, AWS provider docs, and research-module-wiring.md §Rationale#1 all flag that `s3_bucket_bucket_domain_name` (legacy global form) returns a `307 TemporaryRedirect` on the first cache miss for non-`us-east-1` buckets, breaking that initial request and partially poisoning the cache.
*Rejected*: `s3_bucket_bucket_domain_name` — documented anti-pattern.

**Bucket policy as a separate `aws_s3_bucket_policy` glue resource (with `aws_iam_policy_document` data source)**: Do NOT use the s3-bucket module's inline `policy` / `attach_policy` for the OAC bucket policy.
*Rationale*: The OAC bucket policy must reference `module.cloudfront.cloudfront_distribution_arn` for the `AWS:SourceArn` condition. Inlining via `policy` on the bucket module creates a cycle: bucket -> cloudfront (which depends on bucket's regional domain) -> policy -> bucket. Splitting into a downstream `aws_s3_bucket_policy` resource breaks the cycle cleanly and matches the upstream `terraform-aws-cloudfront/complete` example pattern (research-module-wiring.md §Rationale#3).
*Rejected*: Inline `policy` input on the s3-bucket module (creates cycle). Inline policy combined with OAI legacy path (avoids cycle but uses deprecated mechanism).

**CloudFront default certificate (`*.cloudfront.net`)**: Use `cloudfront_default_certificate = true`; do not provision ACM.
*Rationale*: Sandbox tier — no custom domain in scope. Default cert is free, instantaneous, and AWS pins TLS automatically. Custom domains / ACM are explicitly out-of-scope.
*Rejected*: ACM cert in `us-east-1` + `aliases` — out of scope and adds cost / DNS prerequisites.

**SSE-S3 (AES256) for bucket encryption**: Set `server_side_encryption_configuration = { rule = { apply_server_side_encryption_by_default = { sse_algorithm = "AES256" } } }`.
*Rationale*: Cost-optimised for sandbox — SSE-S3 is free, requires no KMS key management, and still meets the "encryption at rest by default" constitution control. Production tiers should revisit for SSE-KMS.
*Rejected*: SSE-KMS (incurs KMS key cost and grant complexity, unjustified for sandbox). No encryption (would override module-recommended posture and violate §3.2 of the constitution).

**Two separate `metric-alarm` module calls (one per metric)**: Use the `cloudwatch/aws//modules/metric-alarm` submodule twice rather than `metric-alarms-by-multiple-dimensions`.
*Rationale*: Each alarm has distinct semantics (5xx error vs 4xx error), distinct thresholds (5% vs 25%), and a single shared dimension set — the multi-dimension submodule adds complexity for zero benefit at this fan-out. Keeps wiring obvious and per-alarm tuning straightforward.
*Rejected*: `metric-alarms-by-multiple-dimensions` (over-engineered for two heterogeneous alarms). Inline `aws_cloudwatch_metric_alarm` resource (constitution §1.1 forbids raw resources when modules cover the surface area).

**Auto-apply enabled on the workspace**: `auto_apply = true` on `sandbox_consumer_cloudfront-demo-consumer-may29`.
*Rationale*: Sandbox/demo tier; sibling pattern allows auto-apply for low-blast-radius demos (research-workspace.md §Workspace Settings, item 5). Documented as intentional deviation from sibling defaults.
*Rejected*: Manual apply (slows demo iteration with no security benefit at sandbox scale).

### Module Inventory

| Module | Registry Source | Version | Purpose | Conditional | Key Inputs | Key Outputs |
|--------|---------------|---------|---------|-------------|------------|-------------|
| `s3_bucket` | `app.terraform.io/hashi-demos-apj/s3-bucket/aws` | `~> 6.0` | Origin S3 bucket in `ap-southeast-2` storing static content | always | `bucket`, `force_destroy`, `versioning`, `server_side_encryption_configuration`, `attach_deny_insecure_transport_policy`, `control_object_ownership`, `object_ownership`, `block_public_acls`, `block_public_policy`, `ignore_public_acls`, `restrict_public_buckets` | `s3_bucket_id`, `s3_bucket_arn`, `s3_bucket_bucket_regional_domain_name` |
| `cloudfront` | `app.terraform.io/hashi-demos-apj/cloudfront/aws` | `~> 5.0` | Global CloudFront distribution with default OAC | always | `enabled`, `is_ipv6_enabled`, `price_class`, `comment`, `default_root_object`, `wait_for_deployment`, `retain_on_delete`, `create_origin_access_control` (default `s3` entry), `origin`, `default_cache_behavior`, `viewer_certificate` | `cloudfront_distribution_id`, `cloudfront_distribution_arn`, `cloudfront_distribution_domain_name`, `cloudfront_distribution_hosted_zone_id`, `cloudfront_origin_access_controls` |
| `alarm_5xx` | `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm` | `~> 5.7` | CloudWatch alarm on CloudFront `5xxErrorRate > 5%` | always | `alarm_name`, `comparison_operator`, `evaluation_periods`, `threshold`, `period`, `unit`, `namespace`, `metric_name`, `statistic`, `dimensions`, `treat_missing_data` | `cloudwatch_metric_alarm_arn`, `cloudwatch_metric_alarm_id` |
| `alarm_4xx` | `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm` | `~> 5.7` | CloudWatch alarm on CloudFront `4xxErrorRate > 25%` | always | `alarm_name`, `comparison_operator`, `evaluation_periods`, `threshold`, `period`, `unit`, `namespace`, `metric_name`, `statistic`, `dimensions`, `treat_missing_data` | `cloudwatch_metric_alarm_arn`, `cloudwatch_metric_alarm_id` |

Module versions are pinned with the pessimistic constraint `~> X.Y` per constitution §4.1 / §4.3. Selections are evidence-based: every entry is documented in `research-private-modules.md` (§Modules Identified, §Recommended Versions) as an existing private registry artefact in `hashi-demos-apj` with verified inputs and outputs.

### Glue Resources

| Resource Type | Logical Name | Purpose | Depends On |
|---------------|-------------|---------|------------|
| `random_id` | `bucket_suffix` | Generate a 4-byte hex suffix for the globally-unique S3 bucket name | -- |
| `aws_iam_policy_document` (data) | `s3_origin` | Compose the OAC bucket policy JSON granting `s3:GetObject` to `cloudfront.amazonaws.com` with `AWS:SourceArn = module.cloudfront.cloudfront_distribution_arn` | `module.s3_bucket`, `module.cloudfront` |
| `aws_s3_bucket_policy` | `origin` | Attach the composed OAC policy to the origin bucket; separated from the s3-bucket module to break the bucket -> cloudfront -> policy cycle | `module.s3_bucket`, `data.aws_iam_policy_document.s3_origin` |

`aws_iam_policy_document` is a read-only configuration helper data source (not a managed resource); `random_id` is a utility provider artefact. Both are explicitly permitted alongside `random_string`, `null_resource`, `terraform_data`, and `time_sleep` per constitution §1.1. `aws_s3_bucket_policy` is the only raw managed AWS resource in the stack — its presence is justified by the documented circular-dependency break (research-module-wiring.md §Rationale#3) and is logged as a `[CONSTITUTION DEVIATION]` candidate in §6 with full rationale.

### Workspace Configuration

| Setting | Value | Notes |
|---------|-------|-------|
| Organization | `hashi-demos-apj` | HCP Terraform organization |
| Project | `sandbox` (`prj-QueMgU3LXgV2Ag7s`) | Default execution mode `remote` |
| Workspace | `sandbox_consumer_cloudfront-demo-consumer-may29` | Created out-of-band via UI / management workspace; consumed by `cloud {}` block |
| Execution Mode | `remote` | HCP Terraform managed; matches sibling pattern |
| Auto Apply | `true` | Sandbox / demo tier — intentional deviation from sibling default of `false` |
| Terraform Version | `1.14.8` (workspace pin); `>= 1.14.0` in code | Matches most-recent sibling (`sandbox_consumer_serverlessdemo-rsa`) |
| Working Directory | `null` | Repo root contains the root module |
| Variable Sets | `agent_AWS_Dynamic_Creds` (`varset-9BtXAvxByVGEnHWV`) — **inherited from project scope, no explicit attachment needed** | Provides `TFC_AWS_PROVIDER_AUTH=true`, `TFC_AWS_RUN_ROLE_ARN=arn:aws:iam::855831148133:role/tfstacks-role`, `TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE=aws.workload.identity` (OIDC dynamic credentials, both regions) |
| Policy Sets | -- (none) | Org has zero policy sets configured |
| VCS Connection | none (manual / API trigger) | Not required for this deployment |
| Tags | `["sandbox", "consumer", "cloudfront", "demo"]` | Recommended for workspace discovery |

---

## 3. Module Wiring

### Wiring Diagram

```
random_id.bucket_suffix.hex ───────► module.s3_bucket.bucket
                                          │
                                          │ s3_bucket_bucket_regional_domain_name (string)
                                          ▼
                                     module.cloudfront.origin["s3"].domain_name
                                          │
                                          │ cloudfront_distribution_arn (string)
                                          ▼
                                     data.aws_iam_policy_document.s3_origin
                                       (condition AWS:SourceArn)
                                          │
                                          │ json (string)
                                          ▼
                                     aws_s3_bucket_policy.origin
                                          │
                                          │ bucket = module.s3_bucket.s3_bucket_id
                                          ▼
                                     [attached to origin bucket]

module.s3_bucket.s3_bucket_arn ────► data.aws_iam_policy_document.s3_origin
                                       (statement.resources = "${arn}/*")

module.cloudfront.cloudfront_distribution_id ───► module.alarm_5xx.dimensions.DistributionId
                                              ───► module.alarm_4xx.dimensions.DistributionId
                                              (both with Region = "Global", us_east_1 provider)
```

### Wiring Table

| Source Module | Output | Target Module | Input | Type | Transformation |
|--------------|--------|--------------|-------|------|----------------|
| `random_id.bucket_suffix` | `hex` | `module.s3_bucket` | `bucket` | string | `"${var.name_prefix}-static-${random_id.bucket_suffix.hex}"` interpolation |
| `module.s3_bucket` | `s3_bucket_bucket_regional_domain_name` | `module.cloudfront` | `origin["s3"].domain_name` | string | direct |
| `module.cloudfront` (self-reference) | `origin_access_control["s3"]` | `module.cloudfront` | `origin["s3"].origin_access_control` | string | string literal `"s3"` — key into the OAC map; v5 module internally resolves the OAC id and sets `aws_cloudfront_distribution.origin.origin_access_control_id`. (Confirmed against terraform-aws-cloudfront v5.0.1 `main.tf` and `examples/complete`. The v5 attribute is **`origin_access_control`** — NOT `origin_access_control_id` (which expects an actual ID) and NOT `origin_access_control_key` (v6+ name).) |
| `module.s3_bucket` | `s3_bucket_arn` | `data.aws_iam_policy_document.s3_origin` | `statement.resources` | string | `["${...}/*"]` interpolation |
| `module.s3_bucket` | `s3_bucket_id` | `aws_s3_bucket_policy.origin` | `bucket` | string | direct |
| `module.cloudfront` | `cloudfront_distribution_arn` | `data.aws_iam_policy_document.s3_origin` | `statement.condition.values` (`AWS:SourceArn`) | string | wrapped in `[...]` list |
| `data.aws_iam_policy_document.s3_origin` | `json` | `aws_s3_bucket_policy.origin` | `policy` | string | direct |
| `module.cloudfront` | `cloudfront_distribution_id` | `module.alarm_5xx` | `dimensions.DistributionId` | string | wrapped in `{ DistributionId = ..., Region = "Global" }` |
| `module.cloudfront` | `cloudfront_distribution_id` | `module.alarm_4xx` | `dimensions.DistributionId` | string | wrapped in `{ DistributionId = ..., Region = "Global" }` |

### Provider Configuration

```hcl
# providers.tf

provider "aws" {
  region = "ap-southeast-2"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }

  # Dynamic credentials via HCP Terraform OIDC (TFC_AWS_PROVIDER_AUTH +
  # TFC_AWS_RUN_ROLE_ARN inherited from the agent_AWS_Dynamic_Creds varset
  # attached at the sandbox project scope). No assume_role block required —
  # the workload identity audience handles role assumption.
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }

  # Same OIDC dynamic credentials — the run role assumption is global per run,
  # the alias only changes the regional API endpoint.
}
```

The `module.cloudfront`, `module.alarm_5xx`, and `module.alarm_4xx` blocks all receive `providers = { aws = aws.us_east_1 }`. The `module.s3_bucket`, `data.aws_iam_policy_document.s3_origin`, and `aws_s3_bucket_policy.origin` blocks use the default provider (`ap-southeast-2`).

### Variables

| Variable | Type | Required | Default | Validation | Sensitive | Description |
|----------|------|----------|---------|------------|-----------|-------------|
| `project_name` | `string` | Yes | -- | `length(var.project_name) >= 3 && length(var.project_name) <= 32 && can(regex("^[a-z0-9-]+$", var.project_name))` | No | Project identifier, used in resource names and `default_tags.Project`. Lowercase alphanumeric and hyphens, 3–32 chars. |
| `environment` | `string` | No | `"sandbox"` | `contains(["sandbox","dev","staging","prod"], var.environment)` | No | Deployment tier. Used in `default_tags.Environment` and passed to the s3-bucket module's `environment` input. |
| `name_prefix` | `string` | No | `"cloudfront-demo"` | `can(regex("^[a-z0-9-]+$", var.name_prefix))` | No | Prefix applied to the S3 bucket name and CloudFront comment. |
| `owner` | `string` | Yes | -- | `length(var.owner) > 0` | No | Owning team / individual; populates `default_tags.Owner`. |
| `tags` | `map(string)` | No | `{}` | -- | No | Extra tags merged into the s3-bucket and cloudfront module `tags` inputs. Provider `default_tags` apply on top. |
| `cloudfront_price_class` | `string` | No | `"PriceClass_100"` | `contains(["PriceClass_100","PriceClass_200","PriceClass_All"], var.cloudfront_price_class)` | No | CloudFront edge coverage tier. `PriceClass_100` for cheapest sandbox footprint. |
| `cloudfront_wait_for_deployment` | `bool` | No | `false` | -- | No | If `false`, `terraform apply` returns as soon as CloudFront accepts the change instead of waiting 5–15 minutes for full propagation. |
| `default_root_object` | `string` | No | `"index.html"` | -- | No | Object served when viewers request `/` from the distribution. |
| `alarm_5xx_threshold` | `number` | No | `5` | `var.alarm_5xx_threshold > 0 && var.alarm_5xx_threshold <= 100` | No | Threshold (percent) for the CloudFront `5xxErrorRate` alarm. |
| `alarm_4xx_threshold` | `number` | No | `25` | `var.alarm_4xx_threshold > 0 && var.alarm_4xx_threshold <= 100` | No | Threshold (percent) for the CloudFront `4xxErrorRate` alarm; sandbox-friendly default. |
| `alarm_evaluation_periods` | `number` | No | `2` | `var.alarm_evaluation_periods >= 1` | No | Consecutive periods the metric must breach the threshold before the alarm transitions to `ALARM`. |
| `alarm_period_seconds` | `number` | No | `300` | `contains([60,120,300,600], var.alarm_period_seconds)` | No | Metric aggregation period (seconds) for both alarms. |

This table is the single source of truth for the deployment's input interface (constitution §1.4). `tfvars` files MAY override any non-required variable.

### Outputs

| Output | Type | Source | Description |
|--------|------|--------|-------------|
| `bucket_name` | `string` | `module.s3_bucket.s3_bucket_name` | Origin S3 bucket name (used for object uploads and ARN construction). The s3-bucket v6 module exposes `s3_bucket_name` (not `s3_bucket_id`, which existed in v4 and earlier). |
| `bucket_arn` | `string` | `module.s3_bucket.s3_bucket_arn` | Origin S3 bucket ARN. |
| `bucket_regional_domain_name` | `string` | `module.s3_bucket.s3_bucket_bucket_regional_domain_name` | Region-specific bucket endpoint; surfaced for diagnostics / smoke tests. |
| `distribution_id` | `string` | `module.cloudfront.cloudfront_distribution_id` | CloudFront distribution ID (used as alarm dimension and for cache invalidation calls). |
| `distribution_arn` | `string` | `module.cloudfront.cloudfront_distribution_arn` | CloudFront distribution ARN. |
| `distribution_domain_name` | `string` | `module.cloudfront.cloudfront_distribution_domain_name` | Public `dXXXXXXXX.cloudfront.net` host — primary smoke-test target. |
| `distribution_hosted_zone_id` | `string` | `module.cloudfront.cloudfront_distribution_hosted_zone_id` | Route 53 alias zone ID (always `Z2FDTNDATAQYW2`). Surfaced for downstream DNS work. |
| `alarm_5xx_arn` | `string` | `module.alarm_5xx.cloudwatch_metric_alarm_arn` | ARN of the `5xxErrorRate` alarm. |
| `alarm_4xx_arn` | `string` | `module.alarm_4xx.cloudwatch_metric_alarm_arn` | ARN of the `4xxErrorRate` alarm. |
| `alarm_arns` | `list(string)` | `[module.alarm_5xx..., module.alarm_4xx...]` | Convenience list of both alarm ARNs for downstream notification wiring. |

---

## 4. Security Controls

| Control | Enforcement | Module Config | Reference |
|---------|-------------|---------------|-----------|
| Encryption at rest (S3) | Explicit module config; SSE-S3 (AES256) applied by default to all objects | `module.s3_bucket: server_side_encryption_configuration = { rule = { apply_server_side_encryption_by_default = { sse_algorithm = "AES256" } } }` | CIS AWS 3.0 — 2.1.1 (S3 bucket-level encryption); AWS Well-Architected SEC 8 (Protecting data at rest) |
| Encryption in transit (S3 origin) | Bucket policy denies any request not made over TLS | `module.s3_bucket: attach_deny_insecure_transport_policy = true` | CIS AWS 3.0 — 2.1.2 (S3 SecureTransport); AWS Well-Architected SEC 9 (Protecting data in transit) |
| Encryption in transit (CloudFront viewer) | CloudFront cache behaviour rewrites HTTP to HTTPS; module honours TLS minimum 1.2_2021 | `module.cloudfront: default_cache_behavior.viewer_protocol_policy = "redirect-to-https"`, `viewer_certificate = { cloudfront_default_certificate = true, minimum_protocol_version = "TLSv1.2_2021" }` | AWS Well-Architected SEC 9; CloudFront security best practice (TLS 1.2 minimum) |
| Public access (S3) | Module secure default — all four public-access-block flags ON; honoured | `module.s3_bucket: block_public_acls = true, block_public_policy = true, ignore_public_acls = true, restrict_public_buckets = true` (set explicitly for audit clarity even though defaults match) | CIS AWS 3.0 — 2.1.5 (S3 public access block); AWS Well-Architected SEC 5 (Network and resource access) |
| IAM least privilege (origin access) | OAC bucket policy grants ONLY `s3:GetObject` ONLY on `${bucket_arn}/*` ONLY to `cloudfront.amazonaws.com` ONLY when `AWS:SourceArn` matches the specific distribution ARN | `aws_iam_policy_document.s3_origin` (single statement, single action, scoped resource, scoped condition) → `aws_s3_bucket_policy.origin` | CIS AWS 3.0 — 1.16 (least privilege); AWS Well-Architected SEC 3 (Identity and permissions management) |
| IAM least privilege (deployment) | HCP Terraform OIDC dynamic credentials; no static keys; project-scoped role assumption | Workspace inherits `agent_AWS_Dynamic_Creds` varset (`TFC_AWS_PROVIDER_AUTH`, `TFC_AWS_RUN_ROLE_ARN`); both provider blocks reuse this single run-role | CIS AWS 3.0 — 1.4 (no root access keys); AWS Well-Architected SEC 2 (Identity management — temporary credentials) |
| Object ownership / ACLs disabled | Module secure default — `BucketOwnerEnforced` disables ACLs entirely | `module.s3_bucket: control_object_ownership = true, object_ownership = "BucketOwnerEnforced"` | CIS AWS 3.0 — 2.1.5; AWS S3 Best Practice (ACLs disabled) |
| Versioning (data protection / rollback) | Module input set; enables object version retention even at sandbox tier | `module.s3_bucket: versioning = { enabled = true }` | AWS Well-Architected REL 9 (Back up data); CIS AWS 3.0 — 2.1.3 (S3 versioning) |
| Logging — CloudFront access logs | N/A — explicitly out of scope for sandbox cost optimisation. Distribution still publishes `AWS/CloudFront` CloudWatch metrics by default; alarms cover error-rate observability. | `module.cloudfront: logging_config` not set | AWS Well-Architected SEC 4 (Detect and investigate security events) — accepted gap, logged in §6 |
| Logging — S3 access logs | N/A — sandbox cost optimisation; CloudFront-only access pattern reduces audit need. | `module.s3_bucket: logging` not set | AWS Well-Architected SEC 4 — accepted gap, logged in §6 |
| Monitoring — error rates | CloudWatch alarms on `5xxErrorRate` (>5%) and `4xxErrorRate` (>25%); dimensioned with `Region = "Global"` and created via the `us_east_1` provider so they actually fire | `module.alarm_5xx`, `module.alarm_4xx`: `namespace = "AWS/CloudFront"`, `dimensions = { DistributionId = ..., Region = "Global" }`, `treat_missing_data = "notBreaching"` | AWS Well-Architected OPS 8 / SEC 4 (Detect and investigate); CIS AWS 3.0 — 4.x (CloudWatch alarms family) |
| Tagging | Provider `default_tags` propagate `Project`, `Environment`, `ManagedBy`, `Owner` to every resource the providers manage; module `tags` inputs accept additional per-resource tags via `var.tags` | `provider "aws"` (both blocks) `default_tags`; `module.s3_bucket: tags = var.tags`; `module.cloudfront: tags = var.tags` | Constitution §3.3; AWS Well-Architected OPS 4 (Resource tagging strategy) |
| Force destroy | `force_destroy = false` on the bucket — even at sandbox, prevent accidental object loss; teardown requires explicit empty-bucket step | `module.s3_bucket: force_destroy = false` | AWS Well-Architected REL 9; defence-in-depth |

No `[SECURITY OVERRIDE]` markers — all module secure defaults are honoured. Two `N/A` entries (CloudFront and S3 access logs) are explicit, justified scope omissions captured in §6 as resolved decisions.

---

## 5. Implementation Checklist

- [x] **A: Repository scaffolding** — Create the repo skeleton: `versions.tf` (`required_version = ">= 1.14.0"`, `required_providers` for `aws ~> 6.5` and `random ~> 3.5`), `backend.tf` (`cloud {}` block targeting `hashi-demos-apj` / project `sandbox` / workspace `sandbox_consumer_cloudfront-demo-consumer-may29`), `providers.tf` (default `aws` in `ap-southeast-2` and aliased `aws.us_east_1`, both with `default_tags`), `variables.tf` (every variable from the §3 Variables table), `locals.tf` (naming locals such as `local.bucket_name = "${var.name_prefix}-static-${random_id.bucket_suffix.hex}"`, common tag merges).
  Files: `versions.tf`, `backend.tf`, `providers.tf`, `variables.tf`, `locals.tf`.

- [x] **B: Origin S3 bucket module call** — Add `random_id.bucket_suffix` (4-byte hex) and `module.s3_bucket` in `main.tf`. Wire `bucket = local.bucket_name`, `force_destroy = false`, `versioning = { enabled = true }`, `server_side_encryption_configuration` (AES256), `attach_deny_insecure_transport_policy = true`, `control_object_ownership = true`, `object_ownership = "BucketOwnerEnforced"`, all four `block_*` / `ignore_*` / `restrict_*` flags `= true` (explicit for audit), `environment = var.environment`, `tags = var.tags`. Default provider (no `providers = {}` block needed).
  Files: `main.tf` (created).

- [x] **C: CloudFront distribution module call** — Added `module.cloudfront` in `main.tf` with `providers = { aws = aws.us_east_1 }`. Configured `enabled = true`, `is_ipv6_enabled = true`, `price_class = var.cloudfront_price_class`, `comment = "${var.name_prefix} static content (${var.environment})"`, `default_root_object = var.default_root_object`, `wait_for_deployment = var.cloudfront_wait_for_deployment`, `retain_on_delete = false`. OAC: `create_origin_access_control = true` with an explicit `s3` entry (`description = "OAC for ${var.name_prefix} static origin"`, `origin_type = "s3"`, `signing_behavior = "always"`, `signing_protocol = "sigv4"`). Origin: `origin = { s3 = { domain_name = module.s3_bucket.s3_bucket_bucket_regional_domain_name, origin_access_control = "s3" } }` — verified against terraform-aws-cloudfront v5.0.1 `main.tf` and `examples/complete`: the v5 attribute is **`origin_access_control`** (a string key into the OAC map), NOT `origin_access_control_id` (which the checklist originally specified — that field expects an actual OAC ID, not a key) and NOT `origin_access_control_key` (the v6 name). The module internally resolves the OAC's `id` and sets `aws_cloudfront_distribution.origin.origin_access_control_id`. `default_cache_behavior = { target_origin_id = "s3", viewer_protocol_policy = "redirect-to-https", allowed_methods = ["GET","HEAD"], cached_methods = ["GET","HEAD"], compress = true, use_forwarded_values = false, cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" }` (AWS-managed `CachingOptimized`). `viewer_certificate = { cloudfront_default_certificate = true, minimum_protocol_version = "TLSv1.2_2021" }`. `tags = local.common_tags`. Section 3 wiring table updated with a row documenting the OAC self-reference.
  Files: `main.tf` (modified).

- [x] **D: OAC bucket policy glue** — Add `data.aws_iam_policy_document.s3_origin` (default provider) with one statement: `actions = ["s3:GetObject"]`, `resources = ["${module.s3_bucket.s3_bucket_arn}/*"]`, `principals { type = "Service", identifiers = ["cloudfront.amazonaws.com"] }`, `condition { test = "StringEquals", variable = "AWS:SourceArn", values = [module.cloudfront.cloudfront_distribution_arn] }`. Then add `aws_s3_bucket_policy.origin` (default provider) with `bucket = module.s3_bucket.s3_bucket_id`, `policy = data.aws_iam_policy_document.s3_origin.json`. Place the data source in a new `data.tf` and append the resource block to `main.tf` alongside the modules.
  Files: `data.tf` (created), `main.tf` (modified).

- [x] **E: CloudWatch alarms module calls** — Added `module.alarm_5xx` and `module.alarm_4xx` to `main.tf`, both pinned to `providers = { aws = aws.us_east_1 }` so they query the AWS/CloudFront namespace where it actually publishes. Shared inputs: `comparison_operator = "GreaterThanThreshold"`, `evaluation_periods = var.alarm_evaluation_periods`, `period = var.alarm_period_seconds`, `statistic = "Average"`, `unit = "Percent"`, `namespace = "AWS/CloudFront"`, `dimensions = { DistributionId = module.cloudfront.cloudfront_distribution_id, Region = "Global" }`, `treat_missing_data = "notBreaching"`, `actions_enabled = true`, `alarm_actions = []`, `ok_actions = []` (SNS out of scope), `tags = local.common_tags`. Per-alarm: `alarm_5xx` uses `metric_name = "5xxErrorRate"`, `threshold = var.alarm_5xx_threshold`, name suffix `-cdn-5xx-error-rate`; `alarm_4xx` uses `metric_name = "4xxErrorRate"`, `threshold = var.alarm_4xx_threshold`, name suffix `-cdn-4xx-error-rate`. Verified the metric-alarm submodule input names against `terraform-aws-cloudwatch v5.7.2/modules/metric-alarm/variables.tf` (the cloudwatch private registry module is a direct mirror) — all argument names (`alarm_name`, `alarm_description`, etc.) match the design's wiring table; no rename needed. `terraform fmt -recursive` clean; `terraform init -backend=false` downloaded both alarm submodule copies. `terraform validate` surfaced one pre-existing error from item D (`module.s3_bucket.s3_bucket_id` — the s3-bucket v6 module exposes `s3_bucket_name` not `s3_bucket_id`); flagged for fix in a follow-up but unrelated to item E's added code.
  Files: `main.tf` (modified).

- [x] **F: Outputs** — Populated `outputs.tf` with every output from the §3 Outputs table: `bucket_name`, `bucket_arn`, `bucket_regional_domain_name`, `distribution_id`, `distribution_arn`, `distribution_domain_name`, `distribution_hosted_zone_id`, `alarm_5xx_arn`, `alarm_4xx_arn`, and the convenience `alarm_arns` list (combining both alarm ARNs). Each output has a `description` per constitution §2.4; none are sensitive. Verified each module-output reference against the resolved modules under `.terraform/modules/`: s3-bucket v6 exposes `s3_bucket_name` (NOT `s3_bucket_id` as the original §3 row stated — design table corrected); cloudfront v5 exposes `cloudfront_distribution_{id,arn,domain_name,hosted_zone_id}` as expected; cloudwatch metric-alarm v5.7.2 exposes `cloudwatch_metric_alarm_arn` as expected. This also resolves the pre-existing `module.s3_bucket.s3_bucket_id` reference flagged in Item E (the only other consumer of that output was already updated in Item D's `aws_s3_bucket_policy.origin.bucket` wiring during Item D — re-verified clean here). `terraform fmt -recursive` clean; `terraform validate` passes ("Success! The configuration is valid.").
  Files: `outputs.tf` (created).

- [x] **G: Polish — README and example tfvars** — Replaced the placeholder repo-template `README.md` with consumer-specific deployment documentation: title + 1-paragraph description, ASCII composition diagram (S3 origin -> CloudFront OAC -> Viewer with CloudWatch alarms attached), modules table (private registry source / version / purpose mirroring §2), inputs table (mirroring `variables.tf`), outputs table (mirroring `outputs.tf`), deployment instructions (`terraform login`, workspace prerequisites incl. inherited `agent_AWS_Dynamic_Creds` varset and `auto_apply = true`, `terraform init`, `terraform plan`, `terraform apply`, smoke test via `curl -I https://<distribution_domain_name>/` with note that an HTTP request 301-redirects to HTTPS), cleanup section (`terraform destroy` with the `force_destroy = false` empty-bucket caveat), and security & compliance summary referencing §4 (SSE-S3, public access blocked, OAC SigV4, HTTPS-only, TLSv1.2_2021) plus the documented constitution deviation. Created `terraform.auto.tfvars.example` with sandbox-tier values (`environment = "dev"`, `name_prefix = "demo-cloudfront"`, `owner = "platform-team"`, `project_name = "consumer-cloudfront-demo"`, `cloudfront_price_class = "PriceClass_100"`) and inline guidance reminding operators not to commit secrets through tfvars. `terraform fmt -recursive` clean; `terraform validate` reports "Success! The configuration is valid."
  Files: `README.md` (replaced), `terraform.auto.tfvars.example` (created).

---

## 6. Open Questions

No deferred questions remain — this is a non-interactive E2E run. The following decisions were resolved independently and are recorded here with rationale.

### Resolved decisions

1. **OAI vs OAC** — *Resolved: OAC*. Rationale: AWS-recommended pattern since 2022; private cloudfront v5 module wires it natively via the default `origin_access_control` map; cleaner bucket-policy condition (`AWS:SourceArn` against the specific distribution); supports SSE-KMS origins for future hardening. (research-private-modules.md §Alternatives Considered, research-module-wiring.md §Rationale#2.)

2. **Bucket naming uniqueness** — *Resolved: `random_id` 4-byte hex suffix*. Rationale: Avoids global S3 namespace collisions for repeated sandbox spin-up / tear-downs without baking environment data into the name. Suffix is stable across runs (held in state) so re-applies do not rename the bucket.

3. **`force_destroy` on the origin bucket** — *Resolved: `false`*. Rationale: Even at sandbox, default to safe teardown — an accidental `terraform destroy` should not silently delete uploaded objects. Operators wanting clean teardown can flip this temporarily or run `aws s3 rm` first. Consistent with constitution defence-in-depth posture.

4. **CloudFront access logs and S3 server access logs** — *Resolved: not enabled in scope*. Rationale: Sandbox cost optimisation; CloudWatch error-rate alarms cover the security-monitoring requirement. CloudFront still publishes core `AWS/CloudFront` metrics by default, which the alarms consume. Production tier should re-enable both with a logs-target bucket plus lifecycle policy.

5. **CloudFront viewer certificate** — *Resolved: default `*.cloudfront.net` cert*. Rationale: No custom domain in scope; default cert is free and AWS-managed. `minimum_protocol_version = "TLSv1.2_2021"` is set even though AWS effectively pins TLS for the default cert — keeps the field correct for any future migration to a custom ACM cert.

6. **CloudFront `wait_for_deployment`** — *Resolved: `false` by default (variable-controlled)*. Rationale: Sandbox iteration speed — CloudFront global propagation takes 5–15 minutes per change. Deployment "completion" status is not required to validate Terraform-level correctness. Variable allows flip to `true` for production-style runs.

7. **CloudFront price class** — *Resolved: `PriceClass_100` default (variable-controlled)*. Rationale: Cheapest tier (US, Canada, Europe edges only); appropriate for sandbox demo audiences. Variable allows expansion to `PriceClass_200` or `PriceClass_All` for global demos.

8. **Alarm thresholds (5% for 5xx, 25% for 4xx)** — *Resolved: variable-controlled with sandbox-friendly defaults*. Rationale: Stated in the design brief; 25% for 4xx is intentionally lenient because demos will return 404s on missing assets and we do not want noise in a sandbox. Variables allow tightening for production.

9. **Alarm evaluation periods (2 × 300s)** — *Resolved: variable-controlled, default 2 periods of 300s each*. Rationale: Standard CloudFront alarm shape; reduces flapping on transient spikes; aligns with CloudFront 5-minute aggregation cadence.

10. **`auto_apply = true` on the workspace** — *Resolved: enabled, deviation from sibling default*. Rationale: Sandbox / demo tier — explicitly stated in the design brief; documented in research-workspace.md as an intentional deviation. Reviewers can override at workspace creation if they prefer manual gating.

### Constitution deviations

- **`[CONSTITUTION DEVIATION]` — raw `aws_s3_bucket_policy` resource (constitution §1.1)**: The constitution prohibits raw infrastructure resources outside the glue list (`random_id`, `random_string`, `null_resource`, `terraform_data`, `time_sleep`). `aws_s3_bucket_policy` is a managed AWS resource. Deviation justified: routing the OAC bucket policy through the s3-bucket module's inline `policy` input creates an unbreakable circular dependency (bucket -> cloudfront [needs bucket regional domain] -> bucket policy [needs distribution ARN] -> bucket). The split-resource pattern is explicitly the upstream `terraform-aws-modules/cloudfront/aws/complete` example, recommended by AWS, and the only correct way to wire OAC with the v5/v6 module family. Logged here as a constitution deviation per §8.2; risk rating Low — single read-only `s3:GetObject` permission, scope-locked by `AWS:SourceArn`. Recommended platform-team action: update the constitution glue-resource list to include `aws_s3_bucket_policy` when used solely to break OAC cycles, or surface a registry-side helper module that internalises the pattern.
