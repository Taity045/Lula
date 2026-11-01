resource "azurerm_postgresql_flexible_server" "main" {
  name                          = var.database_server_name
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  version                       = "16"
  administrator_login           = "ordersadmin"
  administrator_password        = var.database_admin_password
  delegated_subnet_id           = var.database_subnet_id
  private_dns_zone_id           = var.database_private_dns_zone_id
  public_network_access_enabled = false
  sku_name                      = "B_Standard_B1ms"
  storage_mb                    = 32768
  backup_retention_days         = 7
  tags                          = local.tags
}

resource "azurerm_postgresql_flexible_server_database" "app" {
  name      = "app"
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
