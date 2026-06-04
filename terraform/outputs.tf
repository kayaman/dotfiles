output "final_url" {
  description = "Public URL serving bootstrap.sh."
  value       = "https://${local.fqdn}"
}

output "one_liner" {
  description = "Drop-in install command for the project README."
  value       = "bash <(curl -fsSL https://${local.fqdn})"
}

output "cloudfront_domain" {
  description = "Underlying CloudFront distribution domain (for debugging)."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "cloudfront_distribution_id" {
  description = "Used by `aws cloudfront create-invalidation`."
  value       = aws_cloudfront_distribution.this.id
}
