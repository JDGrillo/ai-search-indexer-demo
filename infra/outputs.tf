output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "random_suffix" {
  value = random_string.suffix.result
}

output "search_endpoint" {
  value = "https://${azurerm_search_service.main.name}.search.windows.net"
}

output "search_service_name" {
  value = azurerm_search_service.main.name
}

output "storage_account_name" {
  value = azurerm_storage_account.docs.name
}

output "storage_account_resource_id" {
  value = azurerm_storage_account.docs.id
}

output "storage_container_name" {
  value = azurerm_storage_container.documents.name
}

output "openai_endpoint" {
  value = azurerm_cognitive_account.openai.endpoint
}

output "cognitive_account_name" {
  value = azurerm_cognitive_account.openai.name
}

output "openai_deployment_name" {
  value = azurerm_cognitive_deployment.gpt4o.name
}

output "backend_mi_client_id" {
  value = azurerm_user_assigned_identity.backend.client_id
}

output "backend_mi_principal_id" {
  value = azurerm_user_assigned_identity.backend.principal_id
}

output "search_identity_principal_id" {
  value = azurerm_search_service.main.identity[0].principal_id
}

output "function_app_url" {
  value = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_name" {
  value = azurerm_linux_function_app.main.name
}

output "application_insights_name" {
  value = azurerm_application_insights.main.name
}

output "log_analytics_workspace_name" {
  value = azurerm_log_analytics_workspace.main.name
}

output "backend_app_url" {
  value = "https://${azurerm_linux_web_app.backend.default_hostname}"
}

output "backend_app_name" {
  value = azurerm_linux_web_app.backend.name
}

output "frontend_app_url" {
  value = "https://${azurerm_linux_web_app.frontend.default_hostname}"
}

output "frontend_app_name" {
  value = azurerm_linux_web_app.frontend.name
}
