# ============================================================================
# Cognito Module Outputs
# ============================================================================

output "user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  description = "ARN of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.arn
}

output "user_pool_endpoint" {
  description = "Endpoint of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.endpoint
}

output "user_pool_domain" {
  description = "Cognito Hosted UI domain"
  value       = aws_cognito_user_pool_domain.main.domain
}

output "user_pool_domain_cloudfront" {
  description = "CloudFront distribution for Hosted UI"
  value       = aws_cognito_user_pool_domain.main.cloudfront_distribution
}

output "app_client_id" {
  description = "ID of the Cognito App Client"
  value       = aws_cognito_user_pool_client.main.id
}

output "app_client_secret" {
  description = "Secret of the Cognito App Client (sensitive)"
  value       = aws_cognito_user_pool_client.main.client_secret
  sensitive   = true
}

output "oauth_secret_arn" {
  description = "ARN of the OAuth credentials secret in Secrets Manager"
  value       = var.create_oauth_secret ? aws_secretsmanager_secret.oauth_credentials[0].arn : data.aws_secretsmanager_secret.oauth_credentials_existing[0].arn
}

output "oauth_auth_endpoint" {
  description = "OAuth authorization endpoint"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com/oauth2/authorize"
}

output "oauth_token_endpoint" {
  description = "OAuth token endpoint"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com/oauth2/token"
}

output "oauth_issuer" {
  description = "OAuth issuer URL (for OIDC discovery)"
  value       = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "hosted_ui_url" {
  description = "Cognito Hosted UI URL for testing"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com/login?client_id=${aws_cognito_user_pool_client.main.id}&response_type=code&scope=openid+email+profile&redirect_uri=${var.callback_urls[0]}"
}
