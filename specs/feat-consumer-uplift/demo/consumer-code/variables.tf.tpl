variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "demo"
}

variable "project" {
  description = "Project name for resource tagging"
  type        = string
  default     = "consumer-uplift-demo"
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "ap-southeast-2"
}

variable "bucket_prefix" {
  description = "Prefix for the S3 bucket name"
  type        = string
  default     = "uplift-demo"
}

variable "force_destroy" {
  description = "Allow bucket deletion even when non-empty"
  type        = bool
  default     = true
}
