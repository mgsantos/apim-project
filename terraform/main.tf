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
