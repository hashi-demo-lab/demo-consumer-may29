# main.tf — Module composition for the cloudfront-static-content stack.
#
# This file holds the module calls and glue resources that compose the
# CloudFront-fronted static content delivery stack. Per the consumer
# constitution §1.1, all infrastructure is provisioned via private
# registry modules; the only raw resources are documented glue
# (`random_id`) and the OAC bucket policy (added in item D — split out
# to break the bucket -> cloudfront -> policy circular dependency).

# ----------------------------------------------------------------------
# Glue resource: random suffix for the globally-unique bucket name.
# Held in state so the bucket name is stable across applies.
# ----------------------------------------------------------------------
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# ----------------------------------------------------------------------
# Origin S3 bucket — private, encrypted, versioned, OAC-only access.
# Default provider (ap-southeast-2). The OAC bucket policy is attached
# in item D as a separate `aws_s3_bucket_policy` resource to break the
# bucket -> cloudfront -> policy cycle (see consumer-design.md §2).
# ----------------------------------------------------------------------
module "s3_bucket" {
  source  = "app.terraform.io/hashi-demos-apj/s3-bucket/aws"
  version = "~> 6.0"

  bucket        = local.bucket_name
  environment   = var.environment
  force_destroy = false

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  # TLS-only access enforced at the bucket policy layer.
  attach_deny_insecure_transport_policy = true

  # ACLs disabled — bucket owner enforced.
  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  # All four public access block flags set explicitly for audit clarity
  # (module defaults already match, but explicit beats implicit here).
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  tags = local.common_tags
}

# ----------------------------------------------------------------------
# CloudFront distribution — global CDN fronting the S3 origin via OAC.
# Pinned to the us-east-1 provider alias because the CloudFront control
# plane is only addressable in us-east-1, and AWS/CloudFront CloudWatch
# metrics (consumed by the alarms in item E) are published there.
#
# OAC linkage: the v5 module's origin block accepts `origin_access_control`
# as a STRING that is a key into the `origin_access_control` map. The
# module then internally resolves the OAC's `id` and sets
# `origin_access_control_id` on the underlying aws_cloudfront_distribution
# origin. (The checklist's `origin_access_control_id = "s3"` would be
# wrong — that field expects an actual OAC ID. Verified against the v5.0.1
# module main.tf and the `complete` example.)
# ----------------------------------------------------------------------
module "cloudfront" {
  source  = "app.terraform.io/hashi-demos-apj/cloudfront/aws"
  version = "~> 5.0"

  providers = {
    aws = aws.us_east_1
  }

  enabled             = true
  is_ipv6_enabled     = true
  price_class         = var.cloudfront_price_class
  comment             = "${var.name_prefix} static content (${var.environment})"
  default_root_object = var.default_root_object
  wait_for_deployment = var.cloudfront_wait_for_deployment
  retain_on_delete    = false

  # OAC: have the module create a single OAC named "s3" with the recommended
  # SigV4 signing for S3 origins. The origin block below references this
  # entry by key.
  create_origin_access_control = true
  origin_access_control = {
    s3 = {
      description      = "OAC for ${var.name_prefix} static origin"
      origin_type      = "s3"
      signing_behavior = "always"
      signing_protocol = "sigv4"
    }
  }

  # Single S3 origin. `origin_access_control = "s3"` is the v5 module's
  # shorthand: the module looks up the OAC's id from the map above and
  # wires it as the distribution's origin_access_control_id.
  origin = {
    s3 = {
      domain_name           = module.s3_bucket.s3_bucket_bucket_regional_domain_name
      origin_access_control = "s3"
    }
  }

  # Default cache behaviour: HTTPS-only viewers, GET/HEAD only, AWS-managed
  # CachingOptimized policy. `use_forwarded_values = false` is required
  # because we are using a managed cache_policy_id (mutually exclusive
  # with forwarded_values per the upstream module README).
  default_cache_behavior = {
    target_origin_id       = "s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    use_forwarded_values   = false
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS-managed CachingOptimized
  }

  # Default *.cloudfront.net cert (no custom domain in scope). TLS 1.2_2021
  # set explicitly so the field is correct if a future iteration switches
  # to a custom ACM cert.
  viewer_certificate = {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = local.common_tags
}

# ----------------------------------------------------------------------
# [CONSTITUTION DEVIATION] aws_s3_bucket_policy — required to break the OAC
# bucket cycle. See consumer-design.md §6.
#
# Constitution §1.1 prohibits raw managed resources outside the documented
# glue list (`random_id`, `random_string`, `null_resource`, `terraform_data`,
# `time_sleep`). This `aws_s3_bucket_policy` is a managed AWS resource and
# is therefore an explicit, justified deviation: routing the OAC policy
# through the s3-bucket module's inline `policy` input would create an
# unbreakable cycle (bucket -> cloudfront [needs bucket regional domain]
# -> bucket policy [needs distribution ARN] -> bucket). The split-resource
# pattern is the upstream `terraform-aws-modules/cloudfront/aws/complete`
# example, AWS-recommended, and the only correct way to wire OAC with the
# v5/v6 cloudfront module family. Risk: Low — a single read-only
# `s3:GetObject` permission, scope-locked by `AWS:SourceArn` to this
# specific distribution.
# ----------------------------------------------------------------------
resource "aws_s3_bucket_policy" "origin" {
  bucket = module.s3_bucket.s3_bucket_name
  policy = data.aws_iam_policy_document.s3_origin.json
}

# ----------------------------------------------------------------------
# CloudWatch alarms — error-rate observability for the CloudFront
# distribution. Both alarms are pinned to the us-east-1 provider alias
# because the AWS/CloudFront namespace is published only in us-east-1
# (research-private-modules.md §Gotcha — CloudFront metrics region).
# Creating these in ap-southeast-2 would result in alarms that silently
# never fire.
#
# The required `Region = "Global"` dimension on every CloudFront alarm is
# documented in the AWS CloudFront monitoring guide and the cloudwatch
# module's metric-alarm README. Without it, the dimension set does not
# match what CloudFront publishes and the alarm receives no datapoints.
#
# `alarm_actions` and `ok_actions` are intentionally empty lists: SNS is
# explicitly out of scope (consumer-design.md §1, §6 resolved decision 4).
# When notification routing is added in a follow-up, wire the SNS topic
# ARN(s) into both lists.
# ----------------------------------------------------------------------
module "alarm_5xx" {
  source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.0"

  providers = {
    aws = aws.us_east_1
  }

  alarm_name          = "${var.name_prefix}-cdn-5xx-error-rate"
  alarm_description   = "CloudFront 5xx error rate exceeded ${var.alarm_5xx_threshold}% over ${var.alarm_evaluation_periods} periods"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period_seconds
  statistic           = "Average"
  unit                = "Percent"

  namespace   = "AWS/CloudFront"
  metric_name = "5xxErrorRate"
  threshold   = var.alarm_5xx_threshold

  dimensions = {
    DistributionId = module.cloudfront.cloudfront_distribution_id
    Region         = "Global"
  }

  treat_missing_data = "notBreaching"
  actions_enabled    = true
  alarm_actions      = []
  ok_actions         = []

  tags = local.common_tags
}

module "alarm_4xx" {
  source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.0"

  providers = {
    aws = aws.us_east_1
  }

  alarm_name          = "${var.name_prefix}-cdn-4xx-error-rate"
  alarm_description   = "CloudFront 4xx error rate exceeded ${var.alarm_4xx_threshold}% over ${var.alarm_evaluation_periods} periods"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period_seconds
  statistic           = "Average"
  unit                = "Percent"

  namespace   = "AWS/CloudFront"
  metric_name = "4xxErrorRate"
  threshold   = var.alarm_4xx_threshold

  dimensions = {
    DistributionId = module.cloudfront.cloudfront_distribution_id
    Region         = "Global"
  }

  treat_missing_data = "notBreaching"
  actions_enabled    = true
  alarm_actions      = []
  ok_actions         = []

  tags = local.common_tags
}
