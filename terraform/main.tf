locals {
  name = "orders-${var.environment}"

  tags = {
    application = "orders"
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}