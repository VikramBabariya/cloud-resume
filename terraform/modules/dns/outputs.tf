# -----------------------------------------------------------------------------
# modules/dns — Outputs
# -----------------------------------------------------------------------------

output "apex_cname_id" {
  description = "Cloudflare record ID for the root apex (@) CNAME record pointing to CloudFront."
  value       = cloudflare_record.apex.id
}

output "www_cname_id" {
  description = "Cloudflare record ID for the www CNAME record pointing to the apex domain."
  value       = cloudflare_record.www.id
}
