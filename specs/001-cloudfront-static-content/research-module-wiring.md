# Research: Module Wiring for S3 -> CloudFront -> CloudWatch (Static Content Distribution)

## Decision

Use `terraform-aws-modules/s3-bucket/aws ~> 5.13` (origin bucket) + `terraform-aws-modules/cloudfront/aws ~> 6.5` (distribution, with built-in Origin Access Control / OAI) + `clouddrove/cloudwatch-alarms/aws ~> 1.3` (CloudFront alarms in `us-east-1`). The CloudFront module's native `origin_access_control` map (default `s3` entry) covers the modern OAC path; if legacy OAI is mandated, fall back to a stand-alone `aws_cloudfront_origin_access_identity` resource and wire its `iam_arn` into a separate `aws_s3_bucket_policy` resource (the s3-bucket module's `policy` input does not accept module-managed policy fragments at apply time without the chicken-and-egg dependency on the distribution's OAC ID).

Note: Private registry was unreachable in this environment (search returned a 5xx for `acme-corp`). The wiring patterns below use the public `terraform-aws-modules/*` interfaces; private wrappers in this organisation are expected to expose the same input/output names because they pass through to these upstream modules. The implementation phase MUST re-verify against the actual private module surface.

## Modules Identified

- **Origin bucket**: `terraform-aws-modules/s3-bucket/aws` v5.13.0
  - **Purpose**: Origin S3 bucket in `ap-southeast-2` holding static assets
  - **Key inputs**: `bucket`, `region`, `versioning`, `server_side_encryption_configuration`, `attach_policy`, `policy`, `attach_deny_insecure_transport_policy = true`, `block_public_acls = true`, `block_public_policy = true`, `ignore_public_acls = true`, `restrict_public_buckets = true`, `control_object_ownership = true`, `object_ownership = "BucketOwnerEnforced"`
  - **Key outputs** (verified types):
    - `s3_bucket_id` (string) -- bucket name
    - `s3_bucket_arn` (string)
    - `s3_bucket_bucket_regional_domain_name` (string) -- `bucketname.s3.<region>.amazonaws.com` -- **this is the value to feed into CloudFront `origin.domain_name`** (avoids region redirect 307s on first request)
    - `s3_bucket_bucket_domain_name` (string) -- `bucketname.s3.amazonaws.com` (legacy global form, do NOT use)
    - `s3_bucket_region` (string)
    - `s3_bucket_policy` (string) -- present-policy text, only populated if `attach_policy = true`

- **CDN**: `terraform-aws-modules/cloudfront/aws` v6.5.1
  - **Purpose**: Global CloudFront distribution fronting the S3 origin
  - **Key inputs**:
    - `aliases`, `comment`, `default_root_object = "index.html"`, `is_ipv6_enabled = true`, `price_class`, `viewer_certificate`
    - `origin` (`map(object(...))`) -- nested object whose `domain_name` is `string` (required); `origin_access_control_id` (optional string) or `origin_access_control_key` (optional string) ties an origin to an OAC entry from the `origin_access_control` map. The module does NOT expose an `s3_origin_config { origin_access_identity = ... }` legacy field at the top level; for OAI you must inject the path via `custom_origin_config`/raw distribution OR (preferred) accept that this module is OAC-first.
    - `origin_access_control` (`map(object({ description, name, origin_type, signing_behavior, signing_protocol }))`) -- defaults to `{ s3 = { origin_type = "s3", signing_behavior = "always", signing_protocol = "sigv4" } }`. Reference it from an origin via `origin_access_control_key = "s3"`.
    - `default_cache_behavior` (object, required) -- set `viewer_protocol_policy = "redirect-to-https"` (the module default is `"https-only"`), `target_origin_id` matching the key in the `origin` map, `compress = true`, `allowed_methods = ["GET","HEAD"]`, `cached_methods = ["GET","HEAD"]`
    - `web_acl_id` (string, optional)
    - `create_monitoring_subscription = true` -- enables 1-minute additional metrics so percentile/per-region alarms work
    - `realtime_metrics_subscription_status = "Enabled"` (default)
  - **Key outputs** (verified types):
    - `cloudfront_distribution_id` (string) -- **this is the dimension value for CloudWatch alarms**
    - `cloudfront_distribution_arn` (string) -- for tagging / IAM, NOT for alarm dimensions
    - `cloudfront_distribution_domain_name` (string) -- `dxxxx.cloudfront.net` for Route 53 alias
    - `cloudfront_distribution_hosted_zone_id` (string) -- Route 53 alias zone ID (always `Z2FDTNDATAQYW2`)
    - `cloudfront_origin_access_controls` (map) -- the OAC objects created; each entry has the OAC `id` accessible via `module.cloudfront.cloudfront_origin_access_controls["s3"].id` (used to seed the bucket policy if you want to use OAC service-principal `cloudfront.amazonaws.com` with `AWS:SourceArn` condition)

- **Alarms**: `clouddrove/cloudwatch-alarms/aws` v1.3.3 (one module call per alarm)
  - **Purpose**: Static-threshold CloudWatch alarms on CloudFront metrics
  - **Key inputs** (verified types):
    - `alarm_name` (string, required), `alarm_description` (string)
    - `comparison_operator` (string, required), `evaluation_periods` (number, required), `threshold` (number), `period` (number), `statistic` (string)
    - `namespace` (string) -- **MUST be `"AWS/CloudFront"`**
    - `metric_name` (string) -- e.g. `5xxErrorRate`, `4xxErrorRate`, `TotalErrorRate`, `Requests`, `BytesDownloaded`, `OriginLatency` (latter requires `create_monitoring_subscription = true`)
    - `dimensions` (`map(any)`) -- **MUST be `{ DistributionId = <id>, Region = "Global" }`** for CloudFront global metrics
    - `alarm_actions` (list(any)) -- SNS topic ARN(s)
    - `treat_missing_data` (string, default `"missing"`)
  - **Key outputs**: `id` (string), `arn` (string)

- **Glue resources needed (raw)**:
  - `aws_cloudfront_origin_access_identity.this` -- ONLY if business mandates legacy OAI over OAC. Created in the global (`aws.us_east_1`) provider context. Outputs `iam_arn` for the bucket policy and `cloudfront_access_identity_path` for the distribution origin.
  - `aws_s3_bucket_policy.origin` -- separate resource attached to the origin bucket. Required because the policy must reference the CloudFront OAC id / OAI iam_arn, which only exists after the distribution / OAI is created. Putting the policy inline in the s3-bucket module's `policy` input creates a cycle (bucket policy depends on distribution depends on bucket).
  - `data.aws_iam_policy_document.s3_origin` -- builds the policy JSON.
  - `random_id.suffix` (optional) -- 4-byte hex suffix for globally-unique bucket name.

## Wiring Diagram

```
                       ap-southeast-2 (provider: aws)            us-east-1 (provider: aws.us_east_1)
                       ----------------------------------         ---------------------------------------
                       module.origin_bucket (s3-bucket)
                            |
                            | s3_bucket_bucket_regional_domain_name (string)
                            v
                                                                  module.cdn (cloudfront)
                                                                       |
                                                                       | cloudfront_distribution_id (string)
                                                                       v
                                                                  module.alarm_5xx (cloudwatch-alarms)
                                                                  module.alarm_origin_latency (...)

  module.cdn.cloudfront_origin_access_controls["s3"].id ---+
                                                            |
                            data.aws_iam_policy_document   <+
                                       |
                                       | json (string)
                                       v
                            aws_s3_bucket_policy.origin ----> module.origin_bucket.s3_bucket_id (bucket)
```

## Wiring Table

| Source | Output | Target | Input | HCL Type | Transform |
|---|---|---|---|---|---|
| `module.origin_bucket` | `s3_bucket_bucket_regional_domain_name` | `module.cdn` | `origin["s3"].domain_name` | string | direct |
| `module.origin_bucket` | `s3_bucket_id` | `aws_s3_bucket_policy.origin` | `bucket` | string | direct |
| `module.origin_bucket` | `s3_bucket_arn` | `data.aws_iam_policy_document.s3_origin` | `statement.resources` | string | `["${...}/*"]` interpolation |
| `module.cdn` | `cloudfront_origin_access_controls["s3"].id` | `module.cdn` | `origin["s3"].origin_access_control_id` | string | OR set `origin_access_control_key = "s3"` and let the module wire it |
| `module.cdn` | `cloudfront_distribution_arn` | `data.aws_iam_policy_document.s3_origin` | `condition.values` (`AWS:SourceArn`) | string | direct (used in OAC bucket policy condition) |
| `module.cdn` | `cloudfront_distribution_id` | `module.alarm_*` | `dimensions.DistributionId` | string | wrapped in `{ DistributionId = ..., Region = "Global" }` |
| `aws_cloudfront_origin_access_identity.this` (legacy path only) | `iam_arn` | `data.aws_iam_policy_document.s3_origin` | `principals.identifiers` | string | `[oai.iam_arn]` |
| `aws_cloudfront_origin_access_identity.this` (legacy path only) | `cloudfront_access_identity_path` | `module.cdn` (raw distribution if needed) | `s3_origin_config.origin_access_identity` | string | direct |

## Provider Alias Configuration

Two aliased AWS providers are required because (a) the bucket lives in `ap-southeast-2`, and (b) CloudFront, OAC, OAI and CloudFront-namespace CloudWatch alarms are all global services whose API endpoints sit in `us-east-1`.

```hcl
# providers.tf

provider "aws" {
  region = "ap-southeast-2"
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
```

```hcl
# main.tf -- provider passing

module "origin_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.13"
  # implicit default provider = ap-southeast-2
  bucket = "${var.project}-static-${random_id.suffix.hex}"
  # ... see Section "Bucket configuration" below
}

module "cdn" {
  source  = "terraform-aws-modules/cloudfront/aws"
  version = "~> 6.5"
  providers = {
    aws = aws.us_east_1
  }

  origin = {
    s3 = {
      domain_name              = module.origin_bucket.s3_bucket_bucket_regional_domain_name
      origin_id                = "s3-origin"
      origin_access_control_key = "s3"   # references the default OAC entry
    }
  }

  default_cache_behavior = {
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
  }

  default_root_object             = "index.html"
  create_monitoring_subscription  = true   # enables percentile / per-region metrics
  # viewer_certificate, aliases, web_acl_id wired from variables
}

# Bucket policy (OAC path) -- runs in the bucket's region
data "aws_iam_policy_document" "s3_origin" {
  statement {
    sid       = "AllowCloudFrontServicePrincipalReadOnly"
    actions   = ["s3:GetObject"]
    resources = ["${module.origin_bucket.s3_bucket_arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [module.cdn.cloudfront_distribution_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "origin" {
  bucket = module.origin_bucket.s3_bucket_id
  policy = data.aws_iam_policy_document.s3_origin.json
}

# Alarms -- run in us-east-1 because AWS/CloudFront metrics are only published there
module "alarm_5xx_error_rate" {
  source  = "clouddrove/cloudwatch-alarms/aws"
  version = "~> 1.3"
  providers = {
    aws = aws.us_east_1
  }

  alarm_name          = "${var.project}-cdn-5xx-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = 5
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = module.cdn.cloudfront_distribution_id
    Region         = "Global"
  }

  alarm_actions = [var.alarm_topic_arn]
  ok_actions    = [var.alarm_topic_arn]
}
```

### Legacy OAI Variant (only if OAC is disallowed)

```hcl
resource "aws_cloudfront_origin_access_identity" "this" {
  provider = aws.us_east_1
  comment  = "${var.project} static content"
}

# data.aws_iam_policy_document.s3_origin -- replace the principals/condition block:
#   principals {
#     type        = "AWS"
#     identifiers = [aws_cloudfront_origin_access_identity.this.iam_arn]
#   }
#  (and drop the SourceArn condition)
```
The `terraform-aws-modules/cloudfront/aws` v6.x module no longer surfaces `s3_origin_config.origin_access_identity` as a top-level origin attribute (the `origin` object schema only has `custom_origin_config` and `vpc_origin_config`), so the OAI path requires either down-rev'ing the module to a v3.x release that exposed `s3_origin_config`, or replacing `module.cdn` with a raw `aws_cloudfront_distribution`. Recommend OAC.

## Bucket Configuration (origin secure defaults)

```hcl
module "origin_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.13"

  bucket        = "${var.project}-static-${random_id.suffix.hex}"
  force_destroy = false

  # Block all public access (defaults are already true, set explicitly for audit clarity)
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  versioning = { status = "Enabled" }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  attach_deny_insecure_transport_policy = true
  # Do NOT set policy / attach_policy here -- the OAC bucket policy is attached
  # via the separate aws_s3_bucket_policy.origin resource to break the cycle.
}
```

## CloudWatch / CloudFront Metric Reference

| Metric | Namespace | Required Dimensions | Notes |
|---|---|---|---|
| `Requests`, `BytesDownloaded`, `BytesUploaded`, `4xxErrorRate`, `5xxErrorRate`, `TotalErrorRate` | `AWS/CloudFront` | `DistributionId`, `Region = "Global"` | Always available; published only to `us-east-1` |
| `OriginLatency`, `CacheHitRate`, `401ErrorRate`, `403ErrorRate`, `404ErrorRate`, `502ErrorRate`, `503ErrorRate`, `504ErrorRate` | `AWS/CloudFront` | `DistributionId`, `Region = "Global"` | Require `aws_cloudfront_monitoring_subscription` (set `create_monitoring_subscription = true` in the module) |
| Per-edge-region metrics | `AWS/CloudFront` | `DistributionId`, `Region = "<region>"` | Optional; values like `"us-east-1"`, `"eu-west-1"` etc. |

The alarms module accepts `dimensions = map(any)`, so `{ DistributionId = string, Region = string }` is passed directly with no transformation.

## Rationale

1. **`s3_bucket_bucket_regional_domain_name` over `s3_bucket_bucket_domain_name`**: AWS's own provider docs and the s3-bucket module's output description explicitly state "AWS CloudFront allows specifying S3 region-specific endpoint when creating S3 origin, it will prevent redirect issues from CloudFront to S3 Origin URL." The legacy global form returns 307 redirects on first request for buckets outside `us-east-1`, breaking caching for that initial hit.

2. **OAC over OAI**: AWS recommends OAC since 2022; the v6.x module wires it natively via the `origin_access_control` default map and the per-origin `origin_access_control_key` attribute. OAC also enables SSE-KMS-encrypted origins and uses a more auditable `cloudfront.amazonaws.com` service principal with `AWS:SourceArn` condition.

3. **Separate `aws_s3_bucket_policy` resource**: The s3-bucket module supports an inline `policy` input, but using it here would create a circular dependency: the policy needs `module.cdn.cloudfront_distribution_arn` (for the `AWS:SourceArn` condition) or `aws_cloudfront_origin_access_identity.this.iam_arn` (legacy). Both depend on the distribution/OAI, which transitively depend on the bucket via the `domain_name` wiring. Splitting the policy into a downstream `aws_s3_bucket_policy` resource breaks this cycle cleanly. This is the same pattern the upstream `terraform-aws-cloudfront` `complete` example uses (it builds an `aws_iam_policy_document.s3_policy` data source and applies it via a stand-alone resource).

4. **`cloudfront_distribution_id` (not arn) for alarms**: CloudWatch's `AWS/CloudFront` namespace dimension is `DistributionId` (the short hex like `E1A2B3C4D5E6F7`), not the ARN. The `aws_cloudwatch_metric_alarm` resource and the clouddrove module both pass `dimensions` straight to the AWS API, so you must pass the ID, not the ARN.

5. **`Region = "Global"` dimension in `us-east-1`**: CloudFront publishes its global aggregates only to `us-east-1`, with the literal string `"Global"` for the `Region` dimension. Alarms must be created in `us-east-1` (hence the `aws.us_east_1` alias on the alarms module) and use `Region = "Global"` -- not `Region = "us-east-1"` and not omitting the dimension entirely.

6. **Provider aliases via `providers = {}` block**: Modules that internally use the default `aws` provider (both `terraform-aws-modules/cloudfront/aws` and `clouddrove/cloudwatch-alarms/aws` declare a single `aws` provider dependency) accept a `providers = { aws = aws.us_east_1 }` map at the call site. The bucket and bucket-policy stay on the default provider in `ap-southeast-2`. The `aws_iam_policy_document` data source has no region affinity and can sit anywhere.

## Alternatives Considered

| Alternative | Why Not |
|---|---|
| Use `s3_bucket_bucket_domain_name` for the origin | Causes 307 redirects on first cache miss for non-`us-east-1` buckets; documented anti-pattern in the s3-bucket module output description |
| Inline `policy` input on the s3-bucket module | Creates a cycle: bucket -> cdn -> policy -> bucket. The split-resource pattern is what the upstream cloudfront-module `complete` example uses |
| Single AWS provider in `us-east-1` | Forces the bucket into `us-east-1`, violates the data-residency/region requirement for `ap-southeast-2` |
| Single AWS provider in `ap-southeast-2`, no alias | CloudFront and OAC API calls succeed in any region (control plane is global), BUT `AWS/CloudFront` CloudWatch metrics are only published to `us-east-1`, so the alarm resource MUST run with a `us-east-1` provider or it will create the alarm in the wrong region and never fire |
| Build CloudFront raw with `aws_cloudfront_distribution` | Works, but consumer-uplift constitution prefers composing existing modules; module gives free OAC wiring, monitoring subscription, response-headers policies |
| Use `aws_cloudwatch_metric_alarm` directly instead of clouddrove module | Acceptable; the module is a thin wrapper. Use raw resource if private registry has no alarms wrapper -- the wiring and dimension shape is identical |
| Use OAI everywhere (legacy) | OAC is the AWS-recommended path; v6.x cloudfront module does not natively expose `s3_origin_config.origin_access_identity` so OAI requires either an older module version or raw resources |

## Sources

- terraform-aws-modules/s3-bucket/aws v5.13.0 -- input/output reference (registry MCP `get_module_details`)
- terraform-aws-modules/cloudfront/aws v6.5.1 -- input/output reference, `complete` and `mtls` examples (registry MCP `get_module_details`)
- clouddrove/cloudwatch-alarms/aws v1.3.3 -- input/output reference (registry MCP `get_module_details`)
- hashicorp/aws v6.44 provider docs:
  - `aws_cloudfront_origin_access_identity` -- `iam_arn` for bucket-policy principal, `cloudfront_access_identity_path` for distribution
  - `aws_cloudfront_origin_access_control` -- OAC arguments and exported `id`
  - `aws_s3_bucket_policy` -- single-resource-per-bucket constraint (PutBucketPolicy overwrite behaviour)
  - `aws_cloudwatch_metric_alarm` -- `namespace`, `dimensions` map shape
- AWS docs: CloudFront CloudWatch metrics namespace `AWS/CloudFront`, dimensions `DistributionId` and `Region` (with `"Global"` value), region requirement `us-east-1`
- Private registry for `acme-corp` was unreachable in this research session; private wrappers (if any) are expected to mirror the upstream interface and MUST be re-verified during implementation
