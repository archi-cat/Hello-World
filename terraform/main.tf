# ── Resource Group ────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

# ── Container Registry ────────────────────────────────────────────────────────

resource "azurerm_container_registry" "main" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = true
}

# ── Networking ────────────────────────────────────────────────────────────────
# VNet with three subnets:
#   - gateway-subnet   : App Gateway (requires its own dedicated subnet)
#   - web-subnet       : Web App Service VNet integration
#   - api-subnet       : API App Service VNet integration

resource "azurerm_virtual_network" "main" {
  name                = "vnet-hello-world"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = [var.vnet_address_space]
}

resource "azurerm_subnet" "gateway" {
  name                 = "gateway-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.gateway_subnet_prefix]
}

resource "azurerm_subnet" "web" {
  name                 = "web-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.web_subnet_prefix]

  delegation {
    name = "web-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "api" {
  name                 = "api-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.api_subnet_prefix]

  delegation {
    name = "api-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# ── App Gateway ───────────────────────────────────────────────────────────────
# Standard V2 — routes public HTTPS traffic to the web App Service.
# Requires a public IP, a frontend config, a backend pool pointing at the
# web app, an HTTP listener, and a routing rule tying them together.

resource "azurerm_public_ip" "gateway" {
  name                = "pip-hello-world-gateway"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_application_gateway" "main" {
  name                = "agw-hello-world"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = azurerm_subnet.gateway.id
  }

  frontend_ip_configuration {
    name                 = "frontend-ip"
    public_ip_address_id = azurerm_public_ip.gateway.id
  }

  frontend_port {
    name = "port-80"
    port = 80
  }

  # Backend pool points at the web App Service hostname
  backend_address_pool {
    name  = "web-backend-pool"
    fqdns = ["${var.web_app_name}.azurewebsites.net"]
  }

  # Health probe uses the /health endpoint we defined in the web app
  probe {
    name                = "web-health-probe"
    protocol            = "Https"
    host                = "${var.web_app_name}.azurewebsites.net"
    path                = "/health"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
    match {
      status_code = ["200"]
    }
  }

  backend_http_settings {
    name                                = "web-http-settings"
    cookie_based_affinity               = "Disabled"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 30
    pick_host_name_from_backend_address = true
    probe_name                          = "web-health-probe"
  }

  http_listener {
    name                           = "web-listener"
    frontend_ip_configuration_name = "frontend-ip"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "web-routing-rule"
    rule_type                  = "Basic"
    priority                   = 100
    http_listener_name         = "web-listener"
    backend_address_pool_name  = "web-backend-pool"
    backend_http_settings_name = "web-http-settings"
  }
}

# ── Observability ─────────────────────────────────────────────────────────────

resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-hello-world"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "web" {
  name                = "appi-web-hello-world"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
}

resource "azurerm_application_insights" "api" {
  name                = "appi-api-hello-world"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
}

# ── App Service Plan ──────────────────────────────────────────────────────────
# Both App Services share one plan — sufficient for dev/test.

resource "azurerm_service_plan" "main" {
  name                = var.app_service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "B1"
}

# ── Web App Service ───────────────────────────────────────────────────────────

resource "azurerm_linux_web_app" "web" {
  name                = var.web_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = true

  # VNet integration — outbound traffic from web app stays in the VNet
  virtual_network_subnet_id = azurerm_subnet.web.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      docker_image_name        = "${var.acr_name}.azurecr.io/hello-world-web:${var.docker_image_tag}"
      docker_registry_url      = "https://${var.acr_name}.azurecr.io"
      docker_registry_username = azurerm_container_registry.main.admin_username
      docker_registry_password = azurerm_container_registry.main.admin_password
    }
    health_check_path                 = "/health"
    health_check_eviction_time_in_min = 10
  }

  app_settings = {
    WEBSITES_PORT                      = "8000"
    API_URL                            = "https://${var.api_app_name}.azurewebsites.net"
    APPINSIGHTS_INSTRUMENTATIONKEY     = azurerm_application_insights.web.instrumentation_key
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.web.connection_string
  }
}

# ── API App Service ───────────────────────────────────────────────────────────

resource "azurerm_linux_web_app" "api" {
  name                = var.api_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = true

  virtual_network_subnet_id = azurerm_subnet.api.id

  # SystemAssigned identity — this is what the SQL Database grants access to
  identity {
    type = "SystemAssigned"
  }
  
  site_config {
    application_stack {
      docker_image_name        = "${var.acr_name}.azurecr.io/hello-world-api:${var.docker_image_tag}"
      docker_registry_url      = "https://${var.acr_name}.azurecr.io"
      docker_registry_username = azurerm_container_registry.main.admin_username
      docker_registry_password = azurerm_container_registry.main.admin_password
    }
    health_check_path                 = "/health"
    health_check_eviction_time_in_min = 10
  }

  app_settings = {
    WEBSITES_PORT                         = "8000"
    SQL_SERVER                            = "${var.sql_server_name}.database.windows.net"
    SQL_DATABASE                          = var.sql_database_name
    APPINSIGHTS_INSTRUMENTATIONKEY        = azurerm_application_insights.api.instrumentation_key
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.api.connection_string
  }
}

# ── SQL Server + Database ─────────────────────────────────────────────────────

resource "azurerm_mssql_server" "main" {
  name                         = var.sql_server_name
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_login
  administrator_login_password = var.sql_admin_password
  azuread_administrator {
    login_username = var.sql_entra_admin_login
    object_id      = var.sql_entra_admin_object_id
    azuread_authentication_only = false

  }
}

resource "azurerm_mssql_database" "main" {
  name      = var.sql_database_name
  server_id = azurerm_mssql_server.main.id
  sku_name  = "Basic"   # 5 DTUs — matches your chosen tier
  max_size_gb = 2
}

# Allow Azure-internal traffic to reach the SQL server
# (covers App Service outbound via VNet integration)
resource "azurerm_mssql_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# ── Alerting ──────────────────────────────────────────────────────────────────

resource "azurerm_monitor_action_group" "main" {
  name                = "ag-hello-world-dtu-alert"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "dtu-alert"

  email_receiver {
    name          = "admin-email"
    email_address = var.alert_email
  }
}

resource "azurerm_monitor_metric_alert" "dtu" {
  name                = "alert-dtu-85pct"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_mssql_database.main.id]
  description         = "Fires when DTU consumption exceeds 85% for 20 minutes"
  severity            = 2
  frequency           = "PT5M"    # evaluate every 5 minutes
  window_size         = "PT15M"   # over a 15-minute window

  criteria {
    metric_namespace = "Microsoft.Sql/servers/databases"
    metric_name      = "dtu_consumption_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}