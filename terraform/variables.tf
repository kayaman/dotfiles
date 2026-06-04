variable "domain_name" {
  description = "Apex domain of the existing Route53 hosted zone."
  type        = string
  default     = "ai-assisted.dev"
}

variable "subdomain" {
  description = "Subdomain to attach to domain_name; final FQDN is \"<subdomain>.<domain_name>\"."
  type        = string
  default     = "dot"
}

variable "github_owner" {
  description = "GitHub user or org that owns the dotfiles repo."
  type        = string
  default     = "kayaman"
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
  default     = "dotfiles"
}

variable "github_ref" {
  description = "Branch, tag, or commit SHA on the GitHub repo to serve."
  type        = string
  default     = "main"
}

variable "bootstrap_path" {
  description = "Path inside the repo of the script served at /."
  type        = string
  default     = "bootstrap.sh"
}

variable "cache_ttl_seconds" {
  description = "Default CloudFront cache TTL for the bootstrap response."
  type        = number
  default     = 300
}
