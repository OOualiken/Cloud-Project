data "azurerm_client_config" "current" {}

terraform {
  required_version = ">= 0.12.0"
  required_providers {
    azurerm = ">=1.38.0"
  }
}

provider "azurerm" {
  version = ">=1.38.0"

  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
}

locals {
  domain = var.application

  shared_tags = {
    application  = var.application
    deployment   = "terraform"
  }

  app_tags = merge(local.shared_tags, { "environment" = var.environment })
}

# ======================================================================================
# Resource Groups
# ======================================================================================

resource "azurerm_resource_group" "resource_group" {
  location = var.location
  name     = local.domain
  tags     = local.app_tags
}

resource "azurerm_resource_group" "resource_group_function" {
  location = var.location
  name     = "${local.domain}Function"
  tags     = local.app_tags
}

# ======================================================================================
# Storage
# ======================================================================================

resource "azurerm_storage_account" "storage_account" {
  name                     = "${local.domain}storageaccount"
  resource_group_name      = azurerm_resource_group.resource_group_function.name
  location                 = azurerm_resource_group.resource_group_function.location
  account_replication_type = "LRS"
  account_tier             = "Standard"
  account_kind             = "StorageV2"
  tags                     = local.app_tags
}

# ======================================================================================
# Functions App Service Plan
# ======================================================================================

resource "azurerm_app_service_plan" "app_service_plan_function" {
  name                = "${local.domain}AppServicePlanFunctions"
  resource_group_name = azurerm_resource_group.resource_group_function.name
  location            = azurerm_resource_group.resource_group_function.location
  kind                = "FunctionApp"

  sku {
    size = "S1"
    tier = "Standard"
  }

  tags = local.app_tags
}

# ======================================================================================
# FunctionApp
# ======================================================================================

resource "azurerm_function_app" "function_app" {
  name                = "${local.domain}FunctionApp"
  resource_group_name = azurerm_resource_group.resource_group_function.name
  location            = azurerm_resource_group.resource_group_function.location
  storage_connection_string = azurerm_storage_account.storage_account.primary_connection_string
  app_service_plan_id = azurerm_app_service_plan.app_service_plan_function.id

  app_settings = {
    # Runtime configuration
    FUNCTIONS_WORKER_RUNTIME        = "node"
    WEBSITE_NODE_DEFAULT_VERSION    = "~10"
    # Azure Functions configuration
    KeyVaultName                             = azurerm_key_vault.key_vault.name
    AZURE_SERVICEBUS_CONNECTION_STRING       = azurerm_servicebus_namespace.servicebus_namespace.default_primary_connection_string
    AZURE_SERVICEBUS_QUEUE_NAME              = azurerm_servicebus_queue.servicebus_queue.name
  }

  identity {
    type = "SystemAssigned" # to access to the KeyVault
  }

  # set up git deployment
  provisioner "local-exec" {
    command = "./az-cli-login.sh | az functionapp deployment source config --branch master --manual-integration --name ${azurerm_function_app.function_app.name} --repo-url ${var.github_address_fonction_app} --resource-group ${azurerm_resource_group.resource_group_function.name}"
  }

  tags = local.app_tags
}

# ======================================================================================
# Service Bus + Queue
# ======================================================================================

resource "azurerm_servicebus_namespace" "servicebus_namespace" {
  name                = "${local.domain}Servicebus"
  resource_group_name = azurerm_resource_group.resource_group_function.name
  location            = azurerm_resource_group.resource_group_function.location
  sku                 = "Standard"
  tags                = local.app_tags
}

resource "azurerm_servicebus_queue" "servicebus_queue" {
  name                = "${local.domain}queue"
  resource_group_name = azurerm_resource_group.resource_group_function.name
  namespace_name      = azurerm_servicebus_namespace.servicebus_namespace.name
  enable_partitioning = true
}

# ======================================================================================
# KeyVault
# ======================================================================================

resource "azurerm_key_vault" "key_vault" {
  name                        = "${local.domain}Keyvault"
  resource_group_name         = azurerm_resource_group.resource_group.name
  location                    = azurerm_resource_group.resource_group.location
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  enabled_for_disk_encryption = true
  sku_name                    = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.service_principal_object_id

    key_permissions = [
      "get",
      "list",
      "create",
      "delete",
    ]

    secret_permissions = [
      "get",
      "list",
      "set",
      "delete",
    ]
  }

  lifecycle {
    ignore_changes = [access_policy]
  }

  tags = local.app_tags
}

resource "azurerm_key_vault_access_policy" "key_vault_access_policy_function_app" {
  key_vault_id = azurerm_key_vault.key_vault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_function_app.function_app.identity[0].principal_id

  key_permissions = [
    "get",
    "list",
  ]

  secret_permissions = [
    "get",
    "list",
  ]
}

# ======================================================================================
# KeyVault (Secrets)
# ======================================================================================

resource "azurerm_key_vault_secret" "key_vault_secret_basic_authentication_function" {
  name         = "BasicAuthenticationFunction"
  value        = base64encode(format("%s:%s", var.function_username, var.function_password))
  key_vault_id = azurerm_key_vault.key_vault.id
}

# ======================================================================================
# Mysql Server
# ======================================================================================

resource "azurerm_mysql_server" "mysql" {
  name                = "${local.domain}mysqlserver"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location

  sku_name = "B_Gen5_1"

  storage_profile {
    storage_mb            = 5120
    backup_retention_days = 7
    geo_redundant_backup  = "Disabled"
  }

  administrator_login          = var.mysql_server_login
  administrator_login_password = var.mysql_server_password
  version                      = var.mysql_server_version
  ssl_enforcement              = "Disabled"


  tags = local.app_tags
}


resource "azurerm_mysql_firewall_rule" "mysql_firewall" {
  name                = "internet"
  resource_group_name = azurerm_resource_group.resource_group.name
  server_name         = azurerm_mysql_server.mysql.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "255.255.255.255"
}

# ======================================================================================
# Mysql Database
# ======================================================================================

resource "azurerm_mysql_database" "mysql" {
  name                = var.mysql_database_name
  resource_group_name = azurerm_resource_group.resource_group.name
  server_name         = azurerm_mysql_server.mysql.name
  charset             = "utf8"
  collation           = "utf8_unicode_ci"
}

# ======================================================================================
# Container Registry
# ======================================================================================

resource "azurerm_container_registry" "container_registry" {
  name                     = "${local.domain}ContainerRegistry"
  resource_group_name      = azurerm_resource_group.resource_group.name
  location                 = azurerm_resource_group.resource_group.location
  sku                      = "Basic"
  admin_enabled            = true

  provisioner "local-exec" {
    command = "./az-cli-login.sh | az acr build --registry ${self.name} ${var.github_frontend_repository_url} --image ${var.github_frontend_repository_name}:latest "
  }

  tags = local.app_tags
}

# ======================================================================================
# Container Group
# ======================================================================================

resource "azurerm_container_group" "container_group" {
  name                = "${local.domain}ContainerGroup"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  ip_address_type     = "public"
  dns_name_label      = "${local.domain}ContainerGroup"
  os_type             = "Linux"

  image_registry_credential {
    server = "${azurerm_container_registry.container_registry.name}.azurecr.io"
    username = azurerm_container_registry.container_registry.admin_username
    password = azurerm_container_registry.container_registry.admin_password
  }

  container {
    name   = var.github_frontend_repository_name
    image  = "${azurerm_container_registry.container_registry.name}.azurecr.io/${var.github_frontend_repository_name}:latest"
    cpu    = "1"
    memory = "1"

    ports {
      port     = 80
      protocol = "TCP"
    }

    environment_variables = {
      API_URL = "https://${azurerm_app_service.app_service.default_site_hostname}"
    }
  }

  tags = local.app_tags
}

# ======================================================================================
# App Service Plan
# ======================================================================================

resource "azurerm_app_service_plan" "app_service_plan_back" {
  name                = "${local.domain}AppServicePlanBackend"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  kind                = "Linux"
  reserved            = true

  sku {
    tier = "Standard"
    size = "S1"
  }

  tags = local.app_tags
}

# ======================================================================================
# App Service
# ======================================================================================

resource "azurerm_app_service" "app_service" {
  name                = "${local.domain}AppService"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  app_service_plan_id = azurerm_app_service_plan.app_service_plan_back.id

  site_config {
    linux_fx_version = "NODE|10.14"
    always_on = "true"
    app_command_line = "npm run launch"
  }

  provisioner "local-exec" {
    command = "./az-cli-login.sh | az webapp deployment source config --branch master --manual-integration --name ${self.name} --repo-url ${var.github_backend_repository_url} --resource-group ${azurerm_resource_group.resource_group.name}"
  }

  app_settings = {
    MYSQL_HOST = azurerm_mysql_server.mysql.fqdn
    MYSQL_PORT = "3306"
    MYSQL_USERNAME = "${azurerm_mysql_server.mysql.administrator_login}@${azurerm_mysql_server.mysql.name}"
    MYSQL_PASSWORD = azurerm_mysql_server.mysql.administrator_login_password
    MYSQL_DATABASE = var.mysql_database_name
    QUEUE_NAME = azurerm_servicebus_queue.servicebus_queue.name
    AZURE_SERVICEBUS_CONNECTION_STRING = azurerm_servicebus_namespace.servicebus_namespace.default_primary_connection_string
  }

  tags = local.app_tags
}
