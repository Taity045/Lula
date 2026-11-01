output "app_url" {
  description = "Application URL, available after deploy_app is enabled."
  value       = var.deploy_app ? "https://${azurerm_container_app.main[0].ingress[0].fqdn}" : null
}

output "database_host" {
  value = azurerm_postgresql_flexible_server.main.fqdn
}

output "key_vault_uri" {
  value = azurerm_key_vault.main.vault_uri
}
