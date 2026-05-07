output "bucket_id" {
  description = "The name of the S3 bucket"
  value       = module.demo_bucket.s3_bucket_id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = module.demo_bucket.s3_bucket_arn
}

output "bucket_region" {
  description = "The AWS region the bucket resides in"
  value       = module.demo_bucket.s3_bucket_region
}
