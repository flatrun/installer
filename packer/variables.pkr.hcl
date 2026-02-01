variable "version" {
  type        = string
  description = "FlatRun version to install"
  default     = "latest"
}

variable "do_token" {
  type        = string
  description = "DigitalOcean API token"
  sensitive   = true
  default     = env("DIGITALOCEAN_TOKEN")
}

variable "aws_access_key" {
  type        = string
  description = "AWS Access Key ID"
  sensitive   = true
  default     = env("AWS_ACCESS_KEY_ID")
}

variable "aws_secret_key" {
  type        = string
  description = "AWS Secret Access Key"
  sensitive   = true
  default     = env("AWS_SECRET_ACCESS_KEY")
}

variable "aws_region" {
  type        = string
  description = "AWS Region for AMI"
  default     = "us-east-1"
}

locals {
  timestamp    = formatdate("YYYYMMDD-hhmm", timestamp())
  image_name   = "flatrun-${var.version}-${local.timestamp}"
}
