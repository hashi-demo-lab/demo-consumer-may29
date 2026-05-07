# data.tf — Data sources for the cloudfront-static-content stack.
#
# This file holds read-only configuration helper data sources. Per
# consumer-design.md §2 (Glue Resources), `aws_iam_policy_document` is a
# read-only configuration helper (not a managed AWS resource) and is
# permitted alongside the documented glue list in constitution §1.1.

# ----------------------------------------------------------------------
# OAC bucket policy document.
#
# Composes the JSON policy that grants the CloudFront service principal
# read-only access to the S3 origin, scoped to the specific distribution
# via the `AWS:SourceArn` condition. Wired into `aws_s3_bucket_policy.origin`
# (in main.tf) — the split-resource pattern breaks the
# bucket -> cloudfront -> policy circular dependency that would otherwise
# arise from inlining the policy on the s3-bucket module.
# Default provider (ap-southeast-2) — IAM policy documents are region-agnostic
# but the resource that consumes this lives in the bucket's region.
# ----------------------------------------------------------------------
data "aws_iam_policy_document" "s3_origin" {
  statement {
    sid     = "AllowCloudFrontServicePrincipalReadOnly"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${module.s3_bucket.s3_bucket_arn}/*",
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [module.cloudfront.cloudfront_distribution_arn]
    }
  }
}
