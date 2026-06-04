# terraform/

Bootstraps `https://dot.ai-assisted.dev` → `bootstrap.sh` via CloudFront
(custom domain + ACM cert, origin = `raw.githubusercontent.com`, viewer-request
Function rewrites `/` to the repo path).

## Apply

```bash
cd terraform
terraform init
terraform apply
```

CloudFront takes 5–15 minutes after apply finishes to reach `Deployed`. Once
deployed, sanity-check with:

```bash
curl -fsSL https://dot.ai-assisted.dev | head -5   # should be bootstrap.sh
```

## Updating bootstrap.sh

Cache TTL is 5 minutes — push to `main`, wait, and the new content propagates
automatically. For an immediate flush:

```bash
aws cloudfront create-invalidation \
  --distribution-id "$(terraform -chdir=terraform output -raw cloudfront_distribution_id)" \
  --paths '/*'
```

## Cost

CloudFront PriceClass_100 (NA + EU) at low traffic rounds to a few cents per
month; ACM cert is free; the Route53 hosted zone is pre-existing.

## Tearing down

```bash
terraform destroy
```

The DNS records, certificate, and distribution are removed. The hosted zone
itself isn't owned by this module and survives.
