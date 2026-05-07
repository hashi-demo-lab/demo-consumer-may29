provider "aws" {
  region = var.aws_region
}

module "demo_bucket" {
  source  = "__MODULE_SOURCE__"
  version = "__MODULE_VERSION__"

  bucket_prefix = "${var.bucket_prefix}-${var.environment}"
  force_destroy = var.force_destroy

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

  tags = {
    Environment = var.environment
    Application = "consumer-uplift-demo"
    Project     = var.project
    ManagedBy   = "terraform"
    Purpose     = "consumer-uplift-demo"
  }
}
