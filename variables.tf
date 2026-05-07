variable "alarm_4xx_threshold" {
  description = "Threshold (percent) for the CloudFront 4xxErrorRate alarm. Sandbox-friendly default of 25 reduces noise from missing-asset 404s."
  type        = number
  default     = 25

  validation {
    condition     = var.alarm_4xx_threshold > 0 && var.alarm_4xx_threshold <= 100
    error_message = "alarm_4xx_threshold must be a percentage greater than 0 and less than or equal to 100."
  }
}

variable "alarm_5xx_threshold" {
  description = "Threshold (percent) for the CloudFront 5xxErrorRate alarm."
  type        = number
  default     = 5

  validation {
    condition     = var.alarm_5xx_threshold > 0 && var.alarm_5xx_threshold <= 100
    error_message = "alarm_5xx_threshold must be a percentage greater than 0 and less than or equal to 100."
  }
}

variable "alarm_evaluation_periods" {
  description = "Consecutive periods the metric must breach the threshold before the alarm transitions to ALARM."
  type        = number
  default     = 2

  validation {
    condition     = var.alarm_evaluation_periods >= 1
    error_message = "alarm_evaluation_periods must be at least 1."
  }
}

variable "alarm_period_seconds" {
  description = "Metric aggregation period (seconds) for both CloudFront alarms. Must align with CloudWatch supported periods."
  type        = number
  default     = 300

  validation {
    condition     = contains([60, 120, 300, 600], var.alarm_period_seconds)
    error_message = "alarm_period_seconds must be one of 60, 120, 300, or 600 seconds."
  }
}

variable "aws_region_origin" {
  description = "AWS region hosting the S3 origin bucket. Default us-east-1 is reserved for CloudFront global resources via the aliased provider."
  type        = string
  default     = "ap-southeast-2"
}

variable "cloudfront_price_class" {
  description = "CloudFront edge coverage tier. PriceClass_100 (US/CA/EU) is the cheapest option for sandbox use."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "cloudfront_price_class must be one of PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

variable "cloudfront_wait_for_deployment" {
  description = "If false, terraform apply returns as soon as CloudFront accepts the change instead of waiting 5-15 minutes for full propagation."
  type        = bool
  default     = false
}

variable "default_root_object" {
  description = "Object served when viewers request '/' from the distribution."
  type        = string
  default     = "index.html"
}

variable "environment" {
  description = "Deployment tier. Used in default_tags.Environment and propagated to module tags."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of dev, test, staging, or prod."
  }
}

variable "name_prefix" {
  description = "Prefix applied to the S3 bucket name and CloudFront comment. Lowercase alphanumeric and hyphens."
  type        = string
  default     = "cloudfront-demo"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "name_prefix must contain only lowercase letters, digits, and hyphens."
  }
}

variable "owner" {
  description = "Owning team or individual; populates default_tags.Owner."
  type        = string

  validation {
    condition     = length(var.owner) > 0
    error_message = "owner must be a non-empty string."
  }
}

variable "project_name" {
  description = "Project identifier, used in resource names and default_tags.Project. Lowercase alphanumeric and hyphens, 3-32 chars."
  type        = string
  default     = "cloudfront-demo"

  validation {
    condition     = length(var.project_name) >= 3 && length(var.project_name) <= 32 && can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must be 3-32 lowercase alphanumeric or hyphen characters."
  }
}

variable "tags" {
  description = "Extra tags merged into the s3-bucket and cloudfront module tags inputs. Provider default_tags apply on top."
  type        = map(string)
  default     = {}
}
