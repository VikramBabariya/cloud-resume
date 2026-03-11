# ADR 0004: Static Asset Delivery and Network Boundaries

## Context

The frontend consists of static assets (HTML, CSS, JS) hosted in an S3 bucket. We must determine the most secure and performant method to deliver these assets globally while maintaining strict network boundaries.

## Options Considered

- **Public S3 Bucket:** Configuring the bucket for public read access.
- **S3 + CloudFront with Origin Access Control (OAC):** Using a globally distributed Content Delivery Network (CDN) as the public entry point, keeping the S3 bucket entirely private.

## Decision

We will enforce a strict networking boundary using Amazon CloudFront with Origin Access Control (OAC), treating S3 strictly as a private origin.

## Security, FinOps, and Architecture Critique

- **Security (Data in Transit):** CloudFront allows us to attach an AWS Certificate Manager (ACM) SSL/TLS certificate, ensuring all user traffic is encrypted in transit (HTTPS). A public S3 bucket cannot natively host HTTPS on a custom apex domain.
- **Security (Access Control):** By implementing OAC, the S3 bucket policy is configured to explicitly deny all direct public internet access. Assets can only be fetched if the request originates from our specific CloudFront distribution.
- **FinOps & Performance:** CloudFront caches static assets at Edge locations (PoPs) globally. This reduces latency for international users and significantly decreases the number of `GET` requests hitting the S3 origin, further optimizing costs.

## Conceptual Bridge to IaC

In our future Terraform migration, this architecture will be represented using `aws_cloudfront_distribution` and an `aws_s3_bucket_policy` that explicitly grants `s3:GetObject` only to the `cloudfront.amazonaws.com` service principal with a condition matching the distribution's ARN.
