terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstatefloryda"  # must be globally unique
    container_name       = "tfstate"
    key                  = "hello-world-appservice.tfstate"
  }
}