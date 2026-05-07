# cloudfront-static-content

A sandbox-tier Terraform consumer that composes a CloudFront-fronted static content delivery stack from the `hashi-demos-apj` private registry. It provisions a private S3 origin bucket in `ap-southeast-2`, a global CloudFront distribution that serves content from that bucket via Origin Access Control (OAC), and two CloudWatch metric alarms (5xx and 4xx error rates) attached to the distribution. The deployment runs in HCP Terraform under workspace `sandbox_consumer_cloudfront-demo-consumer-may29` with auto-apply enabled and OIDC dynamic AWS credentials. End users access content over HTTPS via the default `*.cloudfront.net` domain.

## Composition

```
                   +--------------------+
   Viewer (HTTPS)  |  CloudFront        |   us-east-1 provider alias
   ─────────────►  |  distribution      |   (control plane + metrics)
                   |  (default cert,    |
                   |   TLSv1.2_2021,    |◄────────────┐
                   |   redirect-to-     |             │
                   |   https)           |             │ AWS/CloudFront metrics
                   +---------+----------+             │ (Region = "Global")
                             │                        │
                             │ OAC (SigV4)            │
                             │ AWS:SourceArn          │
                             ▼                        │
                   +--------------------+   +---------+----------+
                   |  S3 origin bucket  |   |  CloudWatch alarms |
                   |  (ap-southeast-2)  |   |  - 5xxErrorRate>5% |
                   |  SSE-S3 / private  |   |  - 4xxErrorRate>25%|
                   |  TLS-only / OAC    |   |  (us-east-1)       |
                   |  policy            |   +--------------------+
                   +--------------------+
```

The OAC bucket policy is attached as a separate `aws_s3_bucket_policy` resource (rather than inlined on the S3 module) to break the bucket -> cloudfront -> policy circular dependency. See `specs/001-cloudfront-static-content/consumer-design.md` §2 and §6 for the full rationale.

## Modules

| Module call | Source | Version | Purpose |
|-------------|--------|---------|---------|
| `module.s3_bucket` | `app.terraform.io/hashi-demos-apj/s3-bucket/aws` | `~> 6.0` | Private origin bucket in `ap-southeast-2`: SSE-S3, versioned, public access blocked, TLS-only, ACLs disabled. |
| `module.cloudfront` | `app.terraform.io/hashi-demos-apj/cloudfront/aws` | `~> 5.0` | Global CloudFront distribution with default OAC, HTTPS-only viewer policy, default `*.cloudfront.net` certificate, AWS-managed `CachingOptimized` policy. Pinned to `aws.us_east_1`. |
| `module.alarm_5xx` | `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm` | `~> 5.0` | CloudWatch alarm on `AWS/CloudFront` `5xxErrorRate` for the distribution. Pinned to `aws.us_east_1`. |
| `module.alarm_4xx` | `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm` | `~> 5.0` | CloudWatch alarm on `AWS/CloudFront` `4xxErrorRate` for the distribution. Pinned to `aws.us_east_1`. |

See `specs/001-cloudfront-static-content/consumer-design.md` §2 for module selection rationale and the inventory of inputs/outputs consumed.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `owner` | `string` | _required_ | Owning team or individual; populates `default_tags.Owner`. |
| `project_name` | `string` | `"cloudfront-demo"` | Project identifier (3-32 lowercase alphanumeric or hyphen chars). Used in resource names and `default_tags.Project`. |
| `environment` | `string` | `"dev"` | Deployment tier (`dev`, `test`, `staging`, `prod`). Propagated to module tags and `default_tags.Environment`. |
| `name_prefix` | `string` | `"cloudfront-demo"` | Prefix applied to the S3 bucket name and CloudFront comment. Lowercase alphanumeric and hyphens. |
| `tags` | `map(string)` | `{}` | Extra tags merged into module `tags` inputs. Provider `default_tags` are applied on top. |
| `aws_region_origin` | `string` | `"ap-southeast-2"` | Region hosting the S3 origin bucket. CloudFront and its alarms are always deployed via the `us-east-1` provider alias. |
| `cloudfront_price_class` | `string` | `"PriceClass_100"` | CloudFront edge coverage tier (`PriceClass_100`, `PriceClass_200`, `PriceClass_All`). |
| `cloudfront_wait_for_deployment` | `bool` | `false` | If `false`, `terraform apply` returns as soon as CloudFront accepts the change instead of waiting 5-15 minutes for full propagation. |
| `default_root_object` | `string` | `"index.html"` | Object served when viewers request `/` from the distribution. |
| `alarm_5xx_threshold` | `number` | `5` | Threshold (percent) for the `5xxErrorRate` alarm. |
| `alarm_4xx_threshold` | `number` | `25` | Threshold (percent) for the `4xxErrorRate` alarm. Sandbox-friendly default reduces noise from missing-asset 404s. |
| `alarm_evaluation_periods` | `number` | `2` | Consecutive periods the metric must breach the threshold before transitioning to `ALARM`. |
| `alarm_period_seconds` | `number` | `300` | Metric aggregation period (seconds). One of `60`, `120`, `300`, `600`. |

The full canonical interface (with validations) lives in `variables.tf`.

## Outputs

| Name | Type | Description |
|------|------|-------------|
| `bucket_name` | `string` | Origin S3 bucket name (used for object uploads and ARN construction). |
| `bucket_arn` | `string` | Origin S3 bucket ARN. |
| `bucket_regional_domain_name` | `string` | Region-specific bucket endpoint; surfaced for diagnostics. |
| `distribution_id` | `string` | CloudFront distribution identifier (used for cache invalidation calls and as the alarm dimension). |
| `distribution_arn` | `string` | CloudFront distribution ARN. |
| `distribution_domain_name` | `string` | Public `dXXXXXXXX.cloudfront.net` hostname; primary smoke-test target. |
| `distribution_hosted_zone_id` | `string` | Route 53 alias zone ID for the distribution (always `Z2FDTNDATAQYW2`). |
| `alarm_5xx_arn` | `string` | ARN of the `5xxErrorRate` alarm. |
| `alarm_4xx_arn` | `string` | ARN of the `4xxErrorRate` alarm. |
| `alarm_arns` | `list(string)` | Convenience list combining both alarm ARNs for downstream notification wiring. |

## Deployment

### Prerequisites

- HCP Terraform organization `hashi-demos-apj` with a workspace named `sandbox_consumer_cloudfront-demo-consumer-may29` in the `sandbox` project. The workspace must be configured with:
  - Execution mode `remote`
  - Auto apply `true` (sandbox tier; sandbox demo iteration speed)
  - Terraform version `1.14.8`
  - Working directory `null` (root module is the repo root)
  - Inherited variable set `agent_AWS_Dynamic_Creds` providing `TFC_AWS_PROVIDER_AUTH`, `TFC_AWS_RUN_ROLE_ARN`, and `TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE` for OIDC dynamic AWS credentials in both `ap-southeast-2` and `us-east-1`. The variable set is attached at the `sandbox` project scope, so no explicit attachment is required.
- A user-scoped HCP Terraform API token (`terraform login` flow).
- Local Terraform `>= 1.14.0`.

### Authenticate to HCP Terraform

```bash
terraform login app.terraform.io
```

### Initialize and plan

```bash
terraform init

terraform plan -var-file=terraform.auto.tfvars
```

### Apply

The workspace is configured with `auto_apply = true`. A successful queued plan auto-applies on HCP Terraform; no `terraform apply` confirmation step is required from the CLI when the plan is queued from the UI or via `terraform apply` from the CLI:

```bash
terraform apply -var-file=terraform.auto.tfvars
```

A successful apply emits the outputs listed above. Note `wait_for_deployment = false` returns from apply quickly; CloudFront propagation can take 5-15 minutes regardless.

### Smoke test

The `distribution_domain_name` output is the primary smoke-test target. Once propagation is complete, an unauthenticated `HEAD` request from any client should return an HTTP response (typically 403 if no `index.html` has been uploaded, or 200 once content is in place):

```bash
curl -I https://$(terraform output -raw distribution_domain_name)/
```

You should observe TLS 1.2+ and a CloudFront `x-amz-cf-*` response header. An HTTP request should redirect to HTTPS:

```bash
curl -I http://$(terraform output -raw distribution_domain_name)/
# expect: HTTP/1.1 301 Moved Permanently  +  Location: https://...
```

## Cleanup

```bash
terraform destroy -var-file=terraform.auto.tfvars
```

The origin bucket is created with `force_destroy = false`, so any uploaded objects must be removed before destroy will succeed. Empty the bucket with `aws s3 rm s3://$(terraform output -raw bucket_name) --recursive` before re-running destroy.

## Security and Compliance

This stack honours all module secure defaults — no `[SECURITY OVERRIDE]` markers exist in the code. The full control matrix is in `specs/001-cloudfront-static-content/consumer-design.md` §4. Highlights:

- **Encryption at rest (S3)** — SSE-S3 (AES256) applied by default to all objects.
- **Encryption in transit (S3)** — Bucket policy denies any non-TLS request (`attach_deny_insecure_transport_policy = true`).
- **Encryption in transit (CloudFront)** — `viewer_protocol_policy = "redirect-to-https"`, `minimum_protocol_version = "TLSv1.2_2021"`.
- **Public access (S3)** — All four block flags ON (`block_public_acls`, `block_public_policy`, `ignore_public_acls`, `restrict_public_buckets`).
- **Origin access** — CloudFront Origin Access Control (OAC, SigV4); bucket policy grants only `s3:GetObject` only to `cloudfront.amazonaws.com` only when `AWS:SourceArn` matches this distribution.
- **ACLs disabled** — `BucketOwnerEnforced` ownership.
- **Versioning** — Enabled for object retention/rollback.
- **Deployment credentials** — HCP Terraform OIDC dynamic credentials; no static AWS keys.
- **Tagging** — Provider `default_tags` propagate `Project`, `Environment`, `ManagedBy`, `Owner` to every resource.
- **Monitoring** — CloudWatch alarms on `5xxErrorRate` and `4xxErrorRate`, dimensioned with `Region = "Global"` and created in `us-east-1` so they actually fire.

Accepted gaps (sandbox cost optimisation; revisit for production tiers): CloudFront access logs disabled, S3 server-access logs disabled, custom domain / ACM certificate not provisioned, WAFv2 not attached, SNS notification routing not wired into the alarms.

One documented constitution deviation exists: the OAC bucket policy is attached via a raw `aws_s3_bucket_policy` resource (rather than via the s3-bucket module's inline `policy` input) to break the bucket -> cloudfront -> policy cycle. See `specs/001-cloudfront-static-content/consumer-design.md` §6 ("Constitution deviations").

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.5 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.5 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.44.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.8.1 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_alarm_4xx"></a> [alarm\_4xx](#module\_alarm\_4xx) | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.0 |
| <a name="module_alarm_5xx"></a> [alarm\_5xx](#module\_alarm\_5xx) | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.0 |
| <a name="module_cloudfront"></a> [cloudfront](#module\_cloudfront) | app.terraform.io/hashi-demos-apj/cloudfront/aws | ~> 5.0 |
| <a name="module_s3_bucket"></a> [s3\_bucket](#module\_s3\_bucket) | app.terraform.io/hashi-demos-apj/s3-bucket/aws | ~> 6.0 |

## Resources

| Name | Type |
|------|------|
| [aws_s3_bucket_policy.origin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [random_id.bucket_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [aws_iam_policy_document.s3_origin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alarm_4xx_threshold"></a> [alarm\_4xx\_threshold](#input\_alarm\_4xx\_threshold) | Threshold (percent) for the CloudFront 4xxErrorRate alarm. Sandbox-friendly default of 25 reduces noise from missing-asset 404s. | `number` | `25` | no |
| <a name="input_alarm_5xx_threshold"></a> [alarm\_5xx\_threshold](#input\_alarm\_5xx\_threshold) | Threshold (percent) for the CloudFront 5xxErrorRate alarm. | `number` | `5` | no |
| <a name="input_alarm_evaluation_periods"></a> [alarm\_evaluation\_periods](#input\_alarm\_evaluation\_periods) | Consecutive periods the metric must breach the threshold before the alarm transitions to ALARM. | `number` | `2` | no |
| <a name="input_alarm_period_seconds"></a> [alarm\_period\_seconds](#input\_alarm\_period\_seconds) | Metric aggregation period (seconds) for both CloudFront alarms. Must align with CloudWatch supported periods. | `number` | `300` | no |
| <a name="input_aws_region_origin"></a> [aws\_region\_origin](#input\_aws\_region\_origin) | AWS region hosting the S3 origin bucket. Default us-east-1 is reserved for CloudFront global resources via the aliased provider. | `string` | `"ap-southeast-2"` | no |
| <a name="input_cloudfront_price_class"></a> [cloudfront\_price\_class](#input\_cloudfront\_price\_class) | CloudFront edge coverage tier. PriceClass\_100 (US/CA/EU) is the cheapest option for sandbox use. | `string` | `"PriceClass_100"` | no |
| <a name="input_cloudfront_wait_for_deployment"></a> [cloudfront\_wait\_for\_deployment](#input\_cloudfront\_wait\_for\_deployment) | If false, terraform apply returns as soon as CloudFront accepts the change instead of waiting 5-15 minutes for full propagation. | `bool` | `false` | no |
| <a name="input_default_root_object"></a> [default\_root\_object](#input\_default\_root\_object) | Object served when viewers request '/' from the distribution. | `string` | `"index.html"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment tier. Used in default\_tags.Environment and propagated to module tags. | `string` | `"dev"` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix applied to the S3 bucket name and CloudFront comment. Lowercase alphanumeric and hyphens. | `string` | `"cloudfront-demo"` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Owning team or individual; populates default\_tags.Owner. | `string` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Project identifier, used in resource names and default\_tags.Project. Lowercase alphanumeric and hyphens, 3-32 chars. | `string` | `"cloudfront-demo"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags merged into the s3-bucket and cloudfront module tags inputs. Provider default\_tags apply on top. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alarm_4xx_arn"></a> [alarm\_4xx\_arn](#output\_alarm\_4xx\_arn) | ARN of the CloudWatch metric alarm watching the CloudFront 4xxErrorRate metric. |
| <a name="output_alarm_5xx_arn"></a> [alarm\_5xx\_arn](#output\_alarm\_5xx\_arn) | ARN of the CloudWatch metric alarm watching the CloudFront 5xxErrorRate metric. |
| <a name="output_alarm_arns"></a> [alarm\_arns](#output\_alarm\_arns) | Convenience list of both CloudFront error-rate alarm ARNs (5xx and 4xx) for downstream notification wiring. |
| <a name="output_bucket_arn"></a> [bucket\_arn](#output\_bucket\_arn) | ARN of the origin S3 bucket backing the CloudFront distribution. |
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | Name of the origin S3 bucket (used for object uploads and ARN construction). |
| <a name="output_bucket_regional_domain_name"></a> [bucket\_regional\_domain\_name](#output\_bucket\_regional\_domain\_name) | Region-specific endpoint of the origin S3 bucket; surfaced for diagnostics and smoke tests. |
| <a name="output_distribution_arn"></a> [distribution\_arn](#output\_distribution\_arn) | ARN of the CloudFront distribution. |
| <a name="output_distribution_domain_name"></a> [distribution\_domain\_name](#output\_distribution\_domain\_name) | Public dXXXXXXXX.cloudfront.net hostname of the CloudFront distribution; primary smoke-test target. |
| <a name="output_distribution_hosted_zone_id"></a> [distribution\_hosted\_zone\_id](#output\_distribution\_hosted\_zone\_id) | Route 53 alias zone ID for the CloudFront distribution (always Z2FDTNDATAQYW2). Surfaced for downstream DNS work. |
| <a name="output_distribution_id"></a> [distribution\_id](#output\_distribution\_id) | Identifier of the CloudFront distribution (used as alarm dimension and for cache invalidation calls). |
<!-- END_TF_DOCS -->
