output "app_gateway_public_ip" {
  description = "Public IP of the App Gateway — this is your app's entry point"
  value       = azurerm_public_ip.gateway.ip_address
}

output "web_app_url" {
  description = "Direct web App Service URL (bypasses App Gateway)"
  value       = "https://${azurerm_linux_web_app.web.default_hostname}"
}

output "api_app_url" {
  description = "Direct API App Service URL"
  value       = "https://${azurerm_linux_web_app.api.default_hostname}"
}

output "acr_login_server" {
  description = "ACR login server"
  value       = azurerm_container_registry.main.login_server
}

output "acr_admin_username" {
  description = "ACR admin username"
  value       = azurerm_container_registry.main.admin_username
}

output "sql_server_fqdn" {
  description = "SQL Server fully qualified domain name"
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "api_identity_principal_id" {
  description = "The API's Managed Identity principal ID — needed to grant SQL access"
  value       = azurerm_linux_web_app.api.identity[0].principal_id
}

output "api_identity_client_id" {
  description = "API Managed Identity client ID"
  value       = azurerm_linux_web_app.api.identity[0].principal_id
}

output "web_app_insights_key" {
  description = "Web App Insights instrumentation key"
  value       = azurerm_application_insights.web.instrumentation_key
  sensitive   = true
}

output "api_app_insights_key" {
  description = "API App Insights instrumentation key"
  value       = azurerm_application_insights.api.instrumentation_key
  sensitive   = true
} 

output "sql_server_identity_principal_id" {
  description = "SQL server system-assigned identity principal ID — needed to assign Directory Readers role"
  value       = azurerm_mssql_server.main.identity[0].principal_id
}