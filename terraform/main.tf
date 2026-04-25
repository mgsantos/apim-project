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
