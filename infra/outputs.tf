output "alb_dns_name" {
  description = "Public URL of the application (frontend + /api/* backend routes)"
  value       = aws_lb.main.dns_name
}

output "ecr_backend_repository_url" {
  description = "ECR repo URL for the backend image — useful for manual docker push/pull outside CI"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_repository_url" {
  description = "ECR repo URL for the frontend image"
  value       = aws_ecr_repository.frontend.repository_url
}

output "rds_endpoint" {
  description = "RDS connection endpoint (host:port) — for manual psql access via a bastion, not reachable directly from your machine (publicly_accessible = false)"
  value       = aws_db_instance.main.endpoint
}

output "grafana_cloudwatch_access_key_id" {
  description = "Access key ID for Grafana's CloudWatch datasource"
  value       = aws_iam_access_key.grafana_readonly.id
}

output "grafana_cloudwatch_secret_access_key" {
  description = "Secret access key for Grafana's CloudWatch datasource — retrieve once with: terraform output -raw grafana_cloudwatch_secret_access_key"
  value       = aws_iam_access_key.grafana_readonly.secret
  sensitive   = true
}
