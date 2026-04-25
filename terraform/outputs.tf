output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "apim_gateway_url" {
  value = azurerm_api_management.apim.gateway_url
}

output "function_app_url" {
  value = "https://${azurerm_linux_function_app.functions.default_hostname}"
}

output "function_app_name" {
  value = azurerm_linux_function_app.functions.name
}

output "app_insights_instrumentation_key" {
  value     = azurerm_application_insights.ai.instrumentation_key
  sensitive = true
}

output "app_insights_connection_string" {
  value     = azurerm_application_insights.ai.connection_string
  sensitive = true
}
