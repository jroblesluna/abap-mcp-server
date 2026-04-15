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
  value       = module.parameters.sap_endpoints_parameter_name
  sensitive   = true
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
# Cognito Outputs (when enabled)
# ============================================================================

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = var.enable_cognito ? module.cognito[0].user_pool_id : "N/A - Cognito module not enabled"
}

output "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = var.enable_cognito ? module.cognito[0].user_pool_arn : "N/A - Cognito module not enabled"
}

output "cognito_app_client_id" {
  description = "Cognito App Client ID (OAuth Client ID)"
  value       = var.enable_cognito ? module.cognito[0].app_client_id : "N/A - Cognito module not enabled"
}

output "cognito_hosted_ui_domain" {
  description = "Cognito Hosted UI domain"
  value       = var.enable_cognito ? module.cognito[0].user_pool_domain : "N/A - Cognito module not enabled"
}

output "cognito_oauth_endpoints" {
  description = "OAuth endpoints for Cognito"
  value = var.enable_cognito ? {
    auth_endpoint  = module.cognito[0].oauth_auth_endpoint
    token_endpoint = module.cognito[0].oauth_token_endpoint
    issuer         = module.cognito[0].oauth_issuer
  } : {}
}

output "cognito_hosted_ui_url" {
  description = "Direct URL to test Cognito Hosted UI"
  value       = var.enable_cognito ? module.cognito[0].hosted_ui_url : "N/A - Cognito module not enabled"
}

output "cognito_setup_commands" {
  description = "Commands to create users and test Cognito"
  value       = var.enable_cognito ? (<<-EOT
    # Create a test user
    aws cognito-idp admin-create-user \
      --user-pool-id ${module.cognito[0].user_pool_id} \
      --username testuser@example.com \
      --user-attributes Name=email,Value=testuser@example.com Name=email_verified,Value=true \
      --temporary-password TempPassword123! \
      --region ${var.region}

    # Set permanent password
    aws cognito-idp admin-set-user-password \
      --user-pool-id ${module.cognito[0].user_pool_id} \
      --username testuser@example.com \
      --password YourPassword123! \
      --permanent \
      --region ${var.region}

    # Test Hosted UI (open in browser)
    ${module.cognito[0].hosted_ui_url}

    # Disable deletion protection (if you need to destroy)
    aws cognito-idp update-user-pool \
      --user-pool-id ${module.cognito[0].user_pool_id} \
      --deletion-protection INACTIVE \
      --region ${var.region}
  EOT
  ) : "N/A - Cognito module not enabled"
}

output "cognito_app_client_secret" {
  description = "Cognito App Client Secret (OAuth Client Secret) - SENSITIVE"
  value       = var.enable_cognito ? module.cognito[0].app_client_secret : "N/A - Cognito module not enabled"
  sensitive   = true
}

output "hoot_mcp_inspector_config" {
  description = "Complete OAuth configuration for Hoot/MCP Inspector (JSON format)"
  value = var.enable_cognito ? jsonencode({
    transport = "sse"
    url       = "https://${local.application_fqdn}/mcp"
    auth = {
      type = "oauth"
      oauth = {
        authorizationUrl = module.cognito[0].oauth_auth_endpoint
        tokenUrl         = module.cognito[0].oauth_token_endpoint
        clientId         = module.cognito[0].app_client_id
        clientSecret     = "(run: terraform output -raw cognito_app_client_secret)"
        scope            = "openid email profile phone"
        redirectUri      = "http://localhost:8009/oauth/callback"
      }
    }
  }) : "N/A - Cognito module not enabled"
}
