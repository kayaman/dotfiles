# CloudFront-attached ACM certs must live in us-east-1, so the entire stack
# is pinned to that region. Route53 is global, so this doesn't constrain DNS.
provider "aws" {
  region = "us-east-1"
}

locals {
  fqdn         = "${var.subdomain}.${var.domain_name}"
  rewrite_path = "/${var.github_owner}/${var.github_repo}/${var.github_ref}/${var.bootstrap_path}"
}

data "aws_route53_zone" "this" {
  name         = var.domain_name
  private_zone = false
}

# ── ACM certificate (DNS-validated via Route53) ─────────────────
resource "aws_acm_certificate" "cert" {
  domain_name       = local.fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.this.zone_id
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# ── CloudFront Function: rewrite `/` to the bootstrap.sh path ───
resource "aws_cloudfront_function" "rewrite" {
  name    = replace(local.fqdn, ".", "-")
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite `/` to the bootstrap.sh path on the GitHub origin."
  publish = true
  code = templatefile("${path.module}/cf-rewrite.js", {
    rewrite_path = local.rewrite_path
  })
}

# ── Cache policy: short TTL so bootstrap updates propagate fast ─
resource "aws_cloudfront_cache_policy" "short_ttl" {
  name        = "${replace(local.fqdn, ".", "-")}-short-ttl"
  comment     = "Short TTL for ${local.fqdn} bootstrap delivery"
  default_ttl = var.cache_ttl_seconds
  min_ttl     = 0
  max_ttl     = var.cache_ttl_seconds * 12 # bound runaway caching at ~1h

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

# ── CloudFront distribution ─────────────────────────────────────
resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${local.fqdn} -> ${var.github_owner}/${var.github_repo}@${var.github_ref}"
  price_class     = "PriceClass_100" # NA + EU edges; plenty for an installer URL

  aliases = [local.fqdn]

  origin {
    origin_id   = "github-raw"
    domain_name = "raw.githubusercontent.com"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "github-raw"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = aws_cloudfront_cache_policy.short_ttl.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.rewrite.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cert.certificate_arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }
}

# ── Route53 ALIAS records → CloudFront ──────────────────────────
resource "aws_route53_record" "alias_a" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.fqdn
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "alias_aaaa" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.fqdn
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
