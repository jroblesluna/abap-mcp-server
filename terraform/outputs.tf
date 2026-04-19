# ============================================================================
# Terraform Outputs for ABAP Accelerator MCP Server
# ============================================================================

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = module.alb.alb_dns_name
}

output "alb_url" {
  description = "Application Load Balancer URL"
  value       = "https://${module.alb.alb_dns_name}"
}

output "application_fqdn" {
  description = "Application fully qualified domain name"
  value       = local.application_fqdn
}

output "mcp_endpoint_url" {
  description = "MCP endpoint URL to provide to users"
  value       = "https://${local.application_fqdn}/mcp"
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.ecs.service_name
}

output "log_group_name" {
  description = "CloudWatch Log Group name"
  value       = aws_cloudwatch_log_group.app.name
}

output "ca_certificate_secret_name" {
  description = "AWS Secrets Manager secret name for CA certificate"
  value       = module.certificates.secret_name
}

output "sap_endpoints_parameter_name" {
  description = "AWS Parameter Store parameter name for SAP endpoints"
  value       = var.sap_endpoints_parameter
}

output "user_exceptions_parameter_name" {
  description = "AWS Parameter Store parameter name for user exceptions"
  value       = var.user_exceptions_parameter
}

output "certificate_arn" {
  description = "ACM certificate ARN"
  value       = aws_acm_certificate.app.arn
}

output "route53_zone_id_public" {
  description = "Route53 public hosted zone ID"
  value       = data.aws_route53_zone.nonprod_public.zone_id
}

output "route53_zone_id_private" {
  description = "Route53 private hosted zone ID (if using private zone)"
  value       = var.use_private_zone ? data.aws_route53_zone.nonprod_private[0].zone_id : "N/A - using public zone"
}

# ============================================================================
# Configuration for Users (Q Developer / Kiro)
# ============================================================================

output "q_developer_config" {
  description = "Configuration snippet for Q Developer MCP client"
  value = jsonencode({
    mcpServers = {
      "abap-mcp-server" = {
        url       = "https://${local.application_fqdn}/mcp"
        transport = "streamable-http"
        headers = {
          "x-sap-system-id" = "S4H-100" # User should change this
          "x-sap-username"  = "YOUR_USERNAME"
          "x-sap-password"  = "YOUR_PASSWORD"
        }
      }
    }
  })
}

# ============================================================================
# Operations Commands
# ============================================================================

output "monitoring_commands" {
  description = "Commands to monitor the deployment"
  value       = <<-EOT
    # View ECS service status
    aws ecs describe-services \
      --cluster ${module.ecs.cluster_name} \
      --services ${module.ecs.service_name} \
      --region ${var.region} \
      --profile ${var.profile}

    # View logs (last 20 lines)
    aws logs tail ${aws_cloudwatch_log_group.app.name} \
      --follow \
      --region ${var.region} \
      --profile ${var.profile}

    # Check ALB target health
    aws elbv2 describe-target-health \
      --target-group-arn ${module.alb.target_group_arn} \
      --region ${var.region} \
      --profile ${var.profile}

    # Test health endpoint
    curl https://${local.application_fqdn}/health

    # Test MCP endpoint
    curl https://${local.application_fqdn}/mcp
  EOT
}

output "secret_population_commands" {
  description = "Commands to populate secrets in Secrets Manager (Application Account)"
  value       = <<-EOT
    # Populate CA Certificate (for Principal Propagation)
    aws secretsmanager put-secret-value \
      --secret-id ${module.certificates.secret_name} \
      --secret-string '{"ca_cert":"-----BEGIN CERTIFICATE-----\n...","ca_key":"-----BEGIN PRIVATE KEY-----\n..."}' \
      --region ${var.region} \
      --profile ${var.profile}
  EOT
}

output "route53_verification_commands" {
  description = "Commands to verify Route53 DNS records (Route53 Account)"
  value       = <<-EOT
    # Verify public zone records (ACM validation)
    aws route53 list-resource-record-sets \
      --hosted-zone-id ${data.aws_route53_zone.nonprod_public.zone_id} \
      --profile ${var.route53_profile} \
      | grep -A 5 "${var.application_hostname}"

    # Verify application A record
    dig ${local.application_fqdn}

    # Test DNS resolution
    nslookup ${local.application_fqdn}
  EOT
}

# ============================================================================
# Summary
# ============================================================================

output "deployment_summary" {
  description = "Deployment summary"
  value = {
    application_url     = "https://${local.application_fqdn}"
    mcp_endpoint        = "https://${local.application_fqdn}/mcp"
    health_endpoint     = "https://${local.application_fqdn}/health"
    ecr_repository      = var.ecr_repository_url
    ecs_cluster         = module.ecs.cluster_name
    ecs_service         = module.ecs.service_name
    log_group           = aws_cloudwatch_log_group.app.name
    application_account = var.profile
    route53_account     = var.route53_profile
    hosted_zone         = var.route53_hosted_zone_name
    zone_type           = var.use_private_zone ? "private" : "public"
  }
}

# ============================================================================
# OAuth Configuration (Managed Externally)
# ============================================================================
# NOTE: OAuth outputs removed - OAuth infrastructure managed by separate team
# OAuth values configured in terraform.tfvars, not outputs from Terraform-managed resources
