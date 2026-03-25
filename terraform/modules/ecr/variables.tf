variable "repositories" {
  description = <<-EOT
    Map of ECR repositories to create. Key is the repo name suffix
    (e.g. "product-api"), value is an optional config object.

    Example:
      repositories = {
        product-api  = {}
        storefront   = {}
        order-worker = {}
      }
  EOT
  type = map(object({
    # Override the default image retention count for this specific repo.
    image_count_to_keep = optional(number, null)
  }))
}

variable "name_prefix" {
  description = "Prefix prepended to each repository name (e.g. 'cloudnative-commerce'). Results in repos like 'cloudnative-commerce/product-api'."
  type        = string
}

variable "image_tag_mutability" {
  description = <<-EOT
    Whether image tags can be overwritten.
    IMMUTABLE: once pushed, a tag cannot be reused — forces unique tags per build.
    Best practice: always use IMMUTABLE in prod to ensure deploy == what was tested.
    MUTABLE: allows overwriting tags (e.g. 'latest') — simpler for dev workflows.
  EOT
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be 'MUTABLE' or 'IMMUTABLE'."
  }
}

variable "scan_on_push" {
  description = "Enable basic ECR image scanning on every push. Catches known CVEs in OS packages. Enhanced scanning (with Snyk/Inspector) is configured separately."
  type        = bool
  default     = true
}

variable "image_count_to_keep" {
  description = "Default number of tagged images to retain per repository. Older images are deleted by lifecycle policy. Prevents unbounded storage costs."
  type        = number
  default     = 20
}

variable "untagged_image_expiry_days" {
  description = "Days before untagged images (intermediate build layers, failed pushes) are deleted."
  type        = number
  default     = 7
}

variable "tags" {
  description = "Additional tags merged onto all resources."
  type        = map(string)
  default     = {}
}
