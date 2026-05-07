terraform {
  cloud {
    organization = "hashi-demos-apj"

    workspaces {
      name    = "sandbox_consumer_cloudfront-demo-consumer-may29"
      project = "sandbox"
    }
  }
}
