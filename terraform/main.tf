# ── Resource Group ────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

# ── Azure Container Registry ──────────────────────────────────────────────────
resource "azurerm_container_registry" "main" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = true
}

# ── App Service Plan ──────────────────────────────────────────────────────────
resource "azurerm_service_plan" "main" {
  name                = var.app_service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "P0V4"  # Basic tier — cheapest paid tier that supports containers
}

# ── App Service (Web App for Containers) ─────────────────────────────────────
resource "azurerm_linux_web_app" "main" {
  name                = var.app_service_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id

  # Pull image from ACR using admin credentials
  site_config {
    application_stack {
      docker_image_name        = "${var.acr_name}.azurecr.io/hello-world:${var.docker_image_tag}"
      docker_registry_url      = "https://${var.acr_name}.azurecr.io"
      docker_registry_username = azurerm_container_registry.main.admin_username
      docker_registry_password = azurerm_container_registry.main.admin_password
    }

    # Health check endpoint we defined in app.py
    health_check_path = "/health"
  }

  app_settings = {
    WEBSITES_PORT = "8000"  # Tells App Service which port your container listens on
  }

  https_only = true  # Redirect all HTTP traffic to HTTPS
}