variable "aws_region" {
  description = "AWS region for all resources in this environment"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment name — used in resource names and tags"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name — used in resource names and tags"
  type        = string
  default     = "cloudnative-commerce"
}
