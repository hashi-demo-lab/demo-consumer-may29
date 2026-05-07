# Default provider — origin S3 bucket region (ap-southeast-2 by default).
# Authenticates via HCP Terraform OIDC dynamic credentials provided by the
# agent_AWS_Dynamic_Creds variable set inherited from the sandbox project scope
# (TFC_AWS_PROVIDER_AUTH + TFC_AWS_RUN_ROLE_ARN). No static keys, no
# assume_role block required.
provider "aws" {
  region = var.aws_region_origin

  default_tags {
    tags = local.default_tags
  }
}

# Aliased us-east-1 provider for CloudFront control-plane and AWS/CloudFront
# CloudWatch metrics. CloudFront alarms only fire when published to us-east-1.
# Reuses the same OIDC run role — only the regional API endpoint changes.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.default_tags
  }
}
