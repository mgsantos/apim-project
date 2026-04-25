# Random suffixes for globally unique names
resource "random_pet" "suffix" {}

resource "random_string" "storage" {
  length  = 8
  special = false
  upper   = false
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prefix}-${random_pet.suffix.id}"
  location = var.location
}

# Storage Account (required by Azure Functions)
resource "azurerm_storage_account" "storage" {
  name                     = "st${var.prefix}${random_string.storage.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Application Insights (observability)
resource "azurerm_application_insights" "ai" {
  name                = "ai-${var.prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
}

# Service Bus Namespace (Standard SKU for Topics support)
resource "azurerm_servicebus_namespace" "sb" {
  name                = "sb-${var.prefix}-${random_pet.suffix.id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
}

# Service Bus Topic
resource "azurerm_servicebus_topic" "orders" {
  name         = "orders-topic"
  namespace_id = azurerm_servicebus_namespace.sb.id
}

# Service Bus Subscription (processor listens here)
resource "azurerm_servicebus_subscription" "processor" {
  name               = "processor-sub"
  topic_id           = azurerm_servicebus_topic.orders.id
  max_delivery_count = 5
}

# Service Plan (Consumption - free tier)
resource "azurerm_service_plan" "plan" {
  name                = "plan-${var.prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "Y1"
}

# Linux Function App
resource "azurerm_linux_function_app" "functions" {
  name                       = "func-${var.prefix}-${random_pet.suffix.id}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  service_plan_id            = azurerm_service_plan.plan.id
  storage_account_name       = azurerm_storage_account.storage.name
  storage_account_access_key = azurerm_storage_account.storage.primary_access_key

  site_config {
    application_stack {
      python_version = "3.12"
    }
    application_insights_key               = azurerm_application_insights.ai.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.ai.connection_string
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = "python"
    "AzureWebJobsFeatureFlags"       = "EnableWorkerIndexing"
    "SERVICE_BUS_CONNECTION_STRING"   = azurerm_servicebus_namespace.sb.default_primary_connection_string
  }
}

# API Management
resource "azurerm_api_management" "apim" {
  name                = "apim-${var.prefix}-${random_pet.suffix.id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  publisher_name      = "OrderHub Team"
  publisher_email     = var.publisher_email
  sku_name            = "Developer_1"
}

# Orders API
resource "azurerm_api_management_api" "orders" {
  name                = "orders-api"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  revision            = "1"
  display_name        = "Orders API"
  path                = "orders"
  protocols           = ["https"]
  service_url         = "https://${azurerm_linux_function_app.functions.default_hostname}/api"
}

resource "azurerm_api_management_api_operation" "create_order" {
  operation_id        = "create-order"
  api_name            = azurerm_api_management_api.orders.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  display_name        = "Create Order"
  method              = "POST"
  url_template        = "/orders"
}

resource "azurerm_api_management_api_policy" "orders_policy" {
  api_name            = azurerm_api_management_api.orders.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  xml_content         = file("${path.module}/policies/order-policy.xml")
}

# Products API
resource "azurerm_api_management_api" "products" {
  name                = "products-api"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  revision            = "1"
  display_name        = "Products API"
  path                = "products"
  protocols           = ["https"]
  service_url         = "https://${azurerm_linux_function_app.functions.default_hostname}/api"
}

resource "azurerm_api_management_api_operation" "get_products" {
  operation_id        = "get-products"
  api_name            = azurerm_api_management_api.products.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  display_name        = "Get Products"
  method              = "GET"
  url_template        = "/products"
}

resource "azurerm_api_management_api_policy" "products_policy" {
  api_name            = azurerm_api_management_api.products.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  xml_content         = file("${path.module}/policies/product-policy.xml")
}
