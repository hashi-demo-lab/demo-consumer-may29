locals {
  # Standard tags propagated to every resource via provider default_tags.
  # Per constitution §3.3: ManagedBy, Environment, Project, Owner.
  default_tags = {
    ManagedBy   = "terraform"
    Environment = var.environment
    Project     = var.project_name
    Owner       = var.owner
  }

  # Tags merged into module-level `tags` inputs (s3-bucket, cloudfront,
  # alarms). Provider default_tags layer on top automatically.
  common_tags = merge(
    var.tags,
    {
      Application = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
    },
  )

  # Globally-unique S3 origin bucket name. The 4-byte hex suffix comes from
  # random_id.bucket_suffix (declared in item B / main.tf) and is held in
  # state across applies, so the bucket name is stable after first creation.
  bucket_name = "${var.name_prefix}-static-${random_id.bucket_suffix.hex}"
}
