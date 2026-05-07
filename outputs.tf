output "alarm_4xx_arn" {
  description = "ARN of the CloudWatch metric alarm watching the CloudFront 4xxErrorRate metric."
  value       = module.alarm_4xx.cloudwatch_metric_alarm_arn
}

output "alarm_5xx_arn" {
  description = "ARN of the CloudWatch metric alarm watching the CloudFront 5xxErrorRate metric."
  value       = module.alarm_5xx.cloudwatch_metric_alarm_arn
}

output "alarm_arns" {
  description = "Convenience list of both CloudFront error-rate alarm ARNs (5xx and 4xx) for downstream notification wiring."
  value = [
    module.alarm_5xx.cloudwatch_metric_alarm_arn,
    module.alarm_4xx.cloudwatch_metric_alarm_arn,
  ]
}

output "bucket_arn" {
  description = "ARN of the origin S3 bucket backing the CloudFront distribution."
  value       = module.s3_bucket.s3_bucket_arn
}

output "bucket_name" {
  description = "Name of the origin S3 bucket (used for object uploads and ARN construction)."
  value       = module.s3_bucket.s3_bucket_name
}

output "bucket_regional_domain_name" {
  description = "Region-specific endpoint of the origin S3 bucket; surfaced for diagnostics and smoke tests."
  value       = module.s3_bucket.s3_bucket_bucket_regional_domain_name
}

output "distribution_arn" {
  description = "ARN of the CloudFront distribution."
  value       = module.cloudfront.cloudfront_distribution_arn
}

output "distribution_domain_name" {
  description = "Public dXXXXXXXX.cloudfront.net hostname of the CloudFront distribution; primary smoke-test target."
  value       = module.cloudfront.cloudfront_distribution_domain_name
}

output "distribution_hosted_zone_id" {
  description = "Route 53 alias zone ID for the CloudFront distribution (always Z2FDTNDATAQYW2). Surfaced for downstream DNS work."
  value       = module.cloudfront.cloudfront_distribution_hosted_zone_id
}

output "distribution_id" {
  description = "Identifier of the CloudFront distribution (used as alarm dimension and for cache invalidation calls)."
  value       = module.cloudfront.cloudfront_distribution_id
}
