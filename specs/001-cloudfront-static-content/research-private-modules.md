## Research: Private registry modules in `hashi-demos-apj` for CloudFront, S3, and CloudWatch monitoring

### Decision

Use three private registry modules from `hashi-demos-apj` to compose the CloudFront + S3 static content stack: `s3-bucket/aws` v6.0.0 (origin bucket in ap-southeast-2), `cloudfront/aws` v5.0.1 (distribution with OAI in us-east-1 provider context), and `cloudwatch/aws` v5.7.2 with the `metric-alarm` submodule for monitoring. All three exist in the private registry — no public-registry fallback is needed for any component. We will need a small amount of glue (an `aws_iam_policy_document` data source for the OAI bucket policy and `random_id`/`random_pet` for unique bucket naming).

### Modules Identified

#### Module Table

| Component | Module Source | Latest Version | Provider Constraint |
|-----------|---------------|----------------|---------------------|
| S3 origin bucket | `app.terraform.io/hashi-demos-apj/s3-bucket/aws` | **6.0.0** | `aws >= 6.5` |
| CloudFront distribution + OAI / OAC | `app.terraform.io/hashi-demos-apj/cloudfront/aws` | **5.0.1** | `aws >= 5.83` |
| CloudWatch monitoring (metric alarms, log groups) | `app.terraform.io/hashi-demos-apj/cloudwatch/aws` | **5.7.2** | `aws >= 5.81` (mirrors public `terraform-aws-modules/cloudwatch/aws` v5.7.2) |

All three modules are published from `hashi-demo-lab` GitHub repos and are direct mirrors of the well-known `terraform-aws-modules/*` upstream modules — so behaviour and interface match the public docs at the same version.

#### Provider compatibility note

The S3 module requires `aws >= 6.5` while CloudFront and CloudWatch require `aws >= 5.83`/`>= 5.81`. The whole stack must therefore pin `aws >= 6.5` to satisfy the strictest dependency. Two `aws` provider configurations are required (passed via `providers = { aws = aws.us_east_1 }` etc.):

- Default provider: `region = "ap-southeast-2"` for the S3 bucket.
- Aliased provider `aws.us_east_1`: `region = "us-east-1"` for the CloudFront distribution (CloudFront is a global service, but the provider must be configured in `us-east-1` for ACM certs and consistent global resource handling). Note: ACM certs for CloudFront viewer certificates MUST be in `us-east-1` — for a sandbox stack we will use the default CloudFront cert (`cloudfront_default_certificate = true`) and skip ACM entirely.

---

#### Primary Module: `app.terraform.io/hashi-demos-apj/s3-bucket/aws` v6.0.0

- **Purpose**: Provision the private S3 bucket that holds static content (HTML, JS, CSS, images) and serves as the CloudFront origin in ap-southeast-2.
- **Key inputs**:
  - `bucket` (string) — explicit bucket name, OR `bucket_prefix` for terraform-generated unique name.
  - `region` (string) — bucket region; for our use case set to `"ap-southeast-2"` (or rely on the provider region).
  - `environment` (string, **required**) — deployment environment label.
  - `force_destroy` (bool, default `false`) — set `true` for sandbox so `terraform destroy` succeeds with non-empty bucket.
  - `control_object_ownership` (bool, default `true`) and `object_ownership` (default `"BucketOwnerEnforced"`) — disables ACLs (recommended for OAC; for legacy OAI you may need `"ObjectWriter"`).
  - `attach_policy` (bool) + `policy` (string JSON) — used to attach the CloudFront OAI bucket policy.
  - `attach_deny_insecure_transport_policy` (bool) — adds `aws:SecureTransport == true` deny rule (recommended).
  - `server_side_encryption_configuration` (any) — set SSE-S3 (`AES256`) for sandbox; SSE-KMS for production.
  - `versioning` (map(string)) — `{ enabled = true }` recommended even for sandbox to allow rollback.
  - Public access block flags (`block_public_acls`, `block_public_policy`, `ignore_public_acls`, `restrict_public_buckets`) — **all default to `true`** which is the desired secure posture for a CloudFront origin.
- **Key outputs**:
  - `s3_bucket_id` — NOTE: this output is NOT in the documented output list. The documented outputs are below; use `s3_bucket_name` as the bucket id/name.
  - `s3_bucket_name` (string) — bucket name (for OAI bucket policy `Resource` ARN construction).
  - `s3_bucket_arn` (string) — `arn:aws:s3:::<name>` (used in OAI bucket policy).
  - `s3_bucket_bucket_regional_domain_name` (string) — `<name>.s3.ap-southeast-2.amazonaws.com`. **This is the value to feed into CloudFront `origin.domain_name`** to avoid 307 redirect issues for non-us-east-1 buckets.
  - `s3_bucket_bucket_domain_name` (string) — generic `<name>.s3.amazonaws.com` (avoid for non-us-east-1 origins).
  - `s3_bucket_region` (string) — region of the bucket.
  - `s3_bucket_hosted_zone_id` (string) — Route 53 hosted zone ID (not used by CloudFront wiring).
  - `s3_bucket_policy` (string) — only populated when `attach_policy = true`.
- **Secure defaults** (out of the box without extra config):
  - Public access block fully enabled (`block_public_acls`, `block_public_policy`, `ignore_public_acls`, `restrict_public_buckets` all default to `true`).
  - `object_ownership = "BucketOwnerEnforced"` (ACLs disabled).
  - `control_object_ownership = true`.
- **Defaults that are NOT secure and require explicit opt-in**:
  - SSE is **not enabled by default** (`server_side_encryption_configuration` defaults to `{}`). Must pass an SSE config block.
  - TLS-only bucket policy (`attach_deny_insecure_transport_policy`) defaults to `false`. Must set `true` for HTTPS-only access.
  - `versioning` is empty map by default. Must explicitly enable.

#### Primary Module: `app.terraform.io/hashi-demos-apj/cloudfront/aws` v5.0.1

- **Purpose**: Provision the CloudFront distribution, optional OAI (legacy) or OAC (modern), and viewer certificate / cache behaviour.
- **Key inputs**:
  - `enabled` (bool, default `true`) — distribution enabled.
  - `is_ipv6_enabled` (bool, default `null`) — set `true` to enable IPv6.
  - `price_class` (string) — set `"PriceClass_100"` for sandbox/dev (US, Canada, Europe edges only — cheapest).
  - `comment` (string) — distribution comment / description.
  - `default_root_object` (string) — typically `"index.html"` for static sites.
  - `wait_for_deployment` (bool, default `true`) — set `false` for fast iteration in sandbox; CloudFront deployments take 5–15 minutes.
  - `retain_on_delete` (bool, default `false`) — keep at `false` for sandbox to allow clean destroy.
  - `aliases` (list(string)) — alternate CNAMEs (only with custom ACM cert in us-east-1; leave `null` for sandbox using `*.cloudfront.net`).
  - `create_origin_access_identity` (bool, default `false`) and `origin_access_identities` (map(string)) — **legacy OAI**. Map key is the logical name referenced from `origin.s3_origin_config.origin_access_identity`.
  - `create_origin_access_control` (bool, default `false`) and `origin_access_control` (map of object) — **modern OAC** (recommended over OAI by AWS). Default OAC config block already includes an `s3` entry with `signing_behavior = "always"`, `signing_protocol = "sigv4"`, `origin_type = "s3"`.
  - `origin` (any, **required**) — map of origin definitions. For S3 with OAI use:
    ```hcl
    origin = {
      s3_static = {
        domain_name = module.s3_bucket.s3_bucket_bucket_regional_domain_name
        origin_id   = "s3-static"
        s3_origin_config = {
          origin_access_identity = "s3_static"  # references key in origin_access_identities map
        }
      }
    }
    ```
    For OAC use `origin_access_control_id` instead of `s3_origin_config`.
  - `default_cache_behavior` (any, **required**) — at minimum: `target_origin_id`, `viewer_protocol_policy = "redirect-to-https"`, `allowed_methods = ["GET","HEAD"]`, `cached_methods = ["GET","HEAD"]`, `compress = true`. Use AWS managed `cache_policy_id` (e.g., `CachingOptimized` = `658327ea-f89d-4fab-a63d-7e88639e58f6`) and set `use_forwarded_values = false` to avoid the cache-policy/forwarded-values conflict (see Notes section of the module README).
  - `viewer_certificate` (any) — defaults to `{ cloudfront_default_certificate = true, minimum_protocol_version = "TLSv1" }`.
  - `logging_config` (any) — `{ bucket, prefix, include_cookies }` to enable access logs (optional for sandbox).
  - `custom_error_response` (any) — handy for SPAs (map 403/404 → `/index.html`).
  - `web_acl_id` (string) — WAFv2 ARN (skip for sandbox).
- **Key outputs**:
  - `cloudfront_distribution_id` (string) — distribution ID, used as the dimension `DistributionId` in CloudWatch alarms.
  - `cloudfront_distribution_arn` (string) — distribution ARN.
  - `cloudfront_distribution_domain_name` (string) — `dXXXXXXXX.cloudfront.net` — the public URL for end users.
  - `cloudfront_distribution_hosted_zone_id` (string) — well-known `Z2FDTNDATAQYW2` for Route 53 alias records.
  - `cloudfront_distribution_status` (string) — `"Deployed"` when ready.
  - `cloudfront_distribution_etag` (string).
  - `cloudfront_origin_access_identities` (map) — full OAI objects keyed by logical name; each has `iam_arn`, `id`, `cloudfront_access_identity_path`.
  - `cloudfront_origin_access_identity_iam_arns` (list/map of string) — IAM ARNs. **Use these in the S3 bucket policy `Principal.AWS` field for OAI access.**
  - `cloudfront_origin_access_identity_ids` — IDs of the OAIs.
  - `cloudfront_origin_access_controls` / `cloudfront_origin_access_controls_ids` — for OAC.
  - `cloudfront_monitoring_subscription_id` — only when `create_monitoring_subscription = true`.
- **Secure defaults / gotchas**:
  - Default `viewer_certificate.minimum_protocol_version = "TLSv1"` is **NOT secure**. Override to `"TLSv1.2_2021"` (the AWS-recommended minimum) — but only when using a custom ACM certificate. With `cloudfront_default_certificate = true` AWS forces the `*.cloudfront.net` cert and effectively the default protocol; the field is still accepted.
  - Module does NOT auto-write the S3 bucket policy granting OAI/OAC read access. **You must compose this glue yourself** via an `aws_iam_policy_document` data source and pass it into `s3-bucket` module's `policy` + `attach_policy = true`. This is the most common gotcha.
  - `viewer_protocol_policy` default in cache behaviours is `"allow-all"` (HTTP and HTTPS). Always set `"redirect-to-https"` or `"https-only"`.
  - Cache policy + `forwarded_values` conflict: when using a managed `cache_policy_id`, must also set `use_forwarded_values = false`. README explicitly calls this out.
  - CloudFront is global but the provider must run in `us-east-1` for tag and metadata API consistency, plus any ACM cert must live there.
  - OAI is **legacy** — AWS recommends OAC for new deployments. Both work; for a sandbox stack OAI is simpler (single `iam_arn` to drop into bucket policy) and the README example uses it.
  - `wait_for_deployment = true` (default) blocks `terraform apply` for 5–15 minutes per change. Set `false` in sandbox.

#### Primary Module: `app.terraform.io/hashi-demos-apj/cloudwatch/aws` v5.7.2 (use `//modules/metric-alarm` submodule)

- **Purpose**: Create CloudWatch metric alarms on CloudFront and S3 metrics. The root module is a passthrough; all real work happens in submodules:
  - `//modules/metric-alarm` — single metric alarm (one alarm per CloudFront metric).
  - `//modules/metric-alarms-by-multiple-dimensions` — many alarms in one block, varied by dimensions.
  - `//modules/log-group`, `//modules/log-metric-filter`, `//modules/log-stream`, `//modules/composite-alarm`, `//modules/cis-alarms`, etc.
- **Source string for our use**:
  ```hcl
  module "cdn_5xx_alarm" {
    source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
    version = "5.7.2"
    # ...
  }
  ```
- **Key inputs (`metric-alarm` submodule)**:
  - `alarm_name` (string, required).
  - `alarm_description` (string).
  - `comparison_operator` (string, required) — e.g., `"GreaterThanOrEqualToThreshold"`.
  - `evaluation_periods` (number, required) — number of consecutive periods.
  - `threshold` (number).
  - `period` (number) — seconds; CloudFront default metrics resolution is 60s.
  - `unit` (string) — `"Percent"` for `5xxErrorRate`, `"Count"` for raw counts.
  - `namespace` (string, required) — for CloudFront use **`"AWS/CloudFront"`**; for S3 request metrics use `"AWS/S3"`.
  - `metric_name` (string, required) — CloudFront examples: `"5xxErrorRate"`, `"4xxErrorRate"`, `"TotalErrorRate"`, `"Requests"`, `"BytesDownloaded"`, `"BytesUploaded"`. S3 examples: `"NumberOfObjects"`, `"BucketSizeBytes"`.
  - `statistic` (string) — `"Average"`, `"Sum"`, `"Maximum"`, `"Minimum"`, `"SampleCount"`.
  - `dimensions` (map(string)) — for CloudFront: `{ DistributionId = module.cloudfront.cloudfront_distribution_id, Region = "Global" }`. The `Region = "Global"` dimension is **required** for CloudFront metrics — this is a common gotcha.
  - `alarm_actions`, `ok_actions`, `insufficient_data_actions` (list(string)) — SNS topic ARNs.
  - `treat_missing_data` (string, default `"missing"`) — recommend `"notBreaching"` for low-traffic sandbox to avoid false alerts.
  - `actions_enabled` (bool, default `true`).
- **Key outputs (`metric-alarm` submodule)**:
  - `cloudwatch_metric_alarm_arn` (string) — alarm ARN.
  - `cloudwatch_metric_alarm_id` (string) — alarm name (used as ID).
- **Gotcha — CloudFront metrics region**: CloudFront publishes metrics ONLY to `us-east-1` regardless of where the rest of your infrastructure lives. The CloudWatch alarm resource for a CloudFront alarm MUST be created with the `us-east-1` provider alias. Pass `providers = { aws = aws.us_east_1 }` to the `metric-alarm` module block. **Do not** create CloudFront alarms in ap-southeast-2 — they will silently never fire.
- **Gotcha — additional metrics**: The default CloudFront metric set is limited (5 metrics). To get per-region/per-edge-location metrics (`Requests`, `BytesDownloaded` etc. at finer granularity) you must enable additional metrics on the distribution via the CloudFront module's `create_monitoring_subscription = true` and `realtime_metrics_subscription_status = "Enabled"` (already the default in the module). This costs extra (~$0.01 per metric per distribution per month).

### Glue Resources Needed

These are NOT raw service resources, they are configuration helpers and acceptable per the constitution:

- `random_id` or `random_pet` — generate a unique suffix for the bucket name to avoid global S3 namespace collisions. Use as `bucket = "myapp-static-${random_id.suffix.hex}"`.
- `data "aws_iam_policy_document" "s3_oai"` — compose the bucket policy that grants `s3:GetObject` to the CloudFront OAI principal. This is the missing piece between the two modules.
- `data "aws_caller_identity" "current"` — optional, for tagging and policy ARN composition.
- A second `aws` provider block aliased as `us_east_1` for the CloudFront distribution and its CloudWatch alarms.

### Wiring Considerations

```
random_id ──► s3-bucket.bucket
                │
                ├─► s3-bucket.s3_bucket_bucket_regional_domain_name ──► cloudfront.origin[].domain_name
                │
                ├─► s3-bucket.s3_bucket_arn ──┐
                │                              ├─► aws_iam_policy_document.s3_oai
cloudfront.cloudfront_origin_access_identity_iam_arns ──┘
                                               │
                                               └─► s3-bucket.policy + attach_policy = true
                                                   (RECREATES s3-bucket because policy depends on cloudfront,
                                                    which is fine — terraform handles the DAG)

cloudfront.cloudfront_distribution_id ──► cloudwatch metric-alarm.dimensions.DistributionId
                                          (with provider = aws.us_east_1)
```

**Circular dependency note**: There is NO true cycle here. The S3 bucket is created first (just bucket + public access block + SSE), then CloudFront is created referencing the bucket's regional domain name, then a second pass attaches the bucket policy referencing the OAI ARN. Terraform resolves this via the DAG without problems because the bucket *resource* doesn't depend on the policy — only the bucket policy *resource* does.

If using OAC instead of OAI, the bucket policy principal is `cloudfront.amazonaws.com` with a `Condition` block `{ StringEquals = { "AWS:SourceArn" = module.cloudfront.cloudfront_distribution_arn } }`. This still creates a clean dependency direction.

### Secure Default Summary

| Concern | Default? | Action required |
|---------|----------|-----------------|
| S3 public access block (all 4 flags) | Enabled by default | None |
| S3 ACLs disabled (`BucketOwnerEnforced`) | Default | None |
| S3 SSE | NOT enabled | Pass `server_side_encryption_configuration = { rule = { apply_server_side_encryption_by_default = { sse_algorithm = "AES256" } } }` |
| S3 TLS-only bucket policy | NOT enabled | Set `attach_deny_insecure_transport_policy = true` |
| S3 versioning | NOT enabled | Set `versioning = { enabled = true }` |
| CloudFront viewer protocol policy | Default `"allow-all"` | Override per cache behaviour to `"redirect-to-https"` |
| CloudFront TLS minimum | Default `"TLSv1"` (weak) | Override `viewer_certificate.minimum_protocol_version = "TLSv1.2_2021"` (only effective with custom ACM cert; with default cert AWS pins it) |
| CloudFront WAF | Not attached | Skip for sandbox |
| CloudFront access logs | Not enabled | Skip for sandbox to minimise cost |
| CloudFront OAI/OAC | Not created | `create_origin_access_identity = true` + `origin_access_identities` map (sandbox) or `create_origin_access_control = true` (recommended) |
| CloudWatch alarm region for CloudFront | N/A | MUST use `us-east-1` provider alias |

### Gaps That Force Raw Resources

**None for the core path.** Both private modules cover the full surface area. The only "raw" elements needed are:

1. `data "aws_iam_policy_document"` — this is a data source (read-only configuration helper), not a managed resource, and is the standard idiomatic way to compose IAM JSON. Allowed by the constitution.
2. `random_id` / `random_pet` — utility provider, not an AWS resource. Allowed.
3. Provider aliasing — configuration, not a resource.

If WAFv2 protection were required, we would need a separate WAFv2 module (not part of this research scope) and pass its ARN to `cloudfront.web_acl_id`. For sandbox we skip WAF entirely.

If a custom domain were required, we would need an ACM certificate in `us-east-1` and a Route53 record — both can be provisioned via existing private/public modules in a follow-up. For sandbox we use the default `*.cloudfront.net` domain.

### Recommended Versions (pin in `versions.tf` / module blocks)

```hcl
module "s3_bucket" {
  source  = "app.terraform.io/hashi-demos-apj/s3-bucket/aws"
  version = "6.0.0"
  # ...
}

module "cloudfront" {
  source  = "app.terraform.io/hashi-demos-apj/cloudfront/aws"
  version = "5.0.1"
  providers = { aws = aws.us_east_1 }
  # ...
}

module "cdn_5xx_alarm" {
  source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "5.7.2"
  providers = { aws = aws.us_east_1 }
  # ...
}

terraform {
  required_version = ">= 1.5.7"
  required_providers {
    aws    = { source = "hashicorp/aws",    version = ">= 6.5" }
    random = { source = "hashicorp/random", version = ">= 3.5" }
  }
}
```

### Rationale

All three required components are present in the `hashi-demos-apj` private registry as direct mirrors of the well-maintained `terraform-aws-modules/*` upstream modules. Versions are recent (S3 v6.0.0 published 2026-03, CloudFront v5.0.1 published 2025-11, CloudWatch v5.7.2 published 2025-11). Interfaces are well-documented through the public mirrors. The CloudFront module's outputs (`cloudfront_origin_access_identity_iam_arns`) align directly with the inputs needed by the S3 module's bucket policy (`policy` + `attach_policy`). The CloudWatch `metric-alarm` submodule's `dimensions` map cleanly accepts the CloudFront distribution ID output. No interface mismatches require glue beyond the standard `aws_iam_policy_document` data source.

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Public registry `terraform-aws-modules/cloudfront/aws` directly | Same code as private mirror, but org policy / governance prefers private registry sources for traceability. |
| Raw `aws_cloudfront_distribution` + `aws_s3_bucket` resources | Constitution prohibits raw resources in consumer code when private modules cover the surface area. |
| `cloudfront/aws` with **OAC** instead of OAI | OAC is AWS's recommended modern pattern, but the private module's README example and simpler input shape favour OAI for a minimal sandbox. OAC would require also wiring `origin_access_control_id` on the origin block plus `Condition.StringEquals.AWS:SourceArn` in the bucket policy. Either is acceptable; OAI chosen for minimal-cost sandbox simplicity. Recommend revisiting for production. |
| `cloudwatch/aws//modules/cis-alarms` | Targets CloudTrail/Config CIS controls, not CloudFront. Wrong scope for this stack. |
| Skipping CloudWatch alarms entirely | Requirements explicitly call for CloudWatch alarms / metric monitoring on the distribution. |
| Bucket in us-east-1 alongside CloudFront | Requirements specify `ap-southeast-2` for the bucket; this works fine because we use `s3_bucket_bucket_regional_domain_name` (not `s3_bucket_bucket_domain_name`) to avoid CloudFront-to-S3 redirect issues. |

### Sources

- Private registry: `hashi-demos-apj` org module listing (queried via `search_private_modules`).
- Private module details:
  - `app.terraform.io/hashi-demos-apj/s3-bucket/aws` v6.0.0 — VCS: `hashi-demo-lab/terraform-aws-s3-bucket` (mirror of `terraform-aws-modules/terraform-aws-s3-bucket`).
  - `app.terraform.io/hashi-demos-apj/cloudfront/aws` v5.0.1 — VCS: `hashi-demo-lab/terraform-aws-cloudfront` (mirror of `terraform-aws-modules/terraform-aws-cloudfront`).
  - `app.terraform.io/hashi-demos-apj/cloudwatch/aws` v5.7.2 — VCS: `hashi-demo-lab/terraform-aws-cloudwatch` (mirror of `terraform-aws-modules/terraform-aws-cloudwatch`).
- Public registry parity reference: `terraform-aws-modules/cloudwatch/aws` v5.7.2 (submodule interfaces).
- AWS provider docs: `hashicorp/aws` v6.44.0 — `aws_cloudfront_distribution`, `aws_cloudwatch_metric_alarm`, `aws_s3_bucket_*`.
- AWS docs — CloudFront CloudWatch metrics namespace `AWS/CloudFront` and required `Region = "Global"` dimension; alarms must be created in `us-east-1`.
