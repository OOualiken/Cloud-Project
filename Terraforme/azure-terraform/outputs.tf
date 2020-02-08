output "azurerm_mysql_server_fqdn" {
  value = azurerm_mysql_server.mysql.fqdn
}

output "azurerm_container_group_fqdn" {
  value = azurerm_container_group.container_group.fqdn
}

output "azurerm_servicebus_queue_name" {
  value = azurerm_servicebus_queue.servicebus_queue.name
}

output "azurerm_function_app_fqdn" {
  value = azurerm_function_app.function_app.default_hostname
}

output "azurerm_service_app_default_host" {
  value = azurerm_app_service.app_service.default_site_hostname
}
