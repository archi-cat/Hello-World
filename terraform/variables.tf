variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "ukwest"
}

variable "resource_group_name" {
  description = "Main resource group name"
  type        = string
  default     = "rg-hello-world"
}

variable "acr_name" {
  description = "Azure Container Registry name (globally unique, alphanumeric only)"
  type        = string
}

variable "web_app_name" {
  description = "Web App Service name (globally unique)"
  type        = string
}

variable "api_app_name" {
  description = "API App Service name (globally unique)"
  type        = string
}

variable "app_service_plan_name" {
  description = "App Service Plan name"
  type        = string
  default     = "asp-hello-world"
}

variable "sql_server_name" {
  description = "SQL Server name (globally unique)"
  type        = string
}

variable "sql_database_name" {
  description = "SQL Database name"
  type        = string
  default     = "sqldb-hello-world"
}

variable "sql_admin_login" {
  description = "SQL Server administrator username"
  type        = string
  default     = "sqladmin"
}

variable "sql_admin_password" {
  description = "SQL Server administrator password"
  type        = string
  sensitive   = true
}

variable "alert_email" {
  description = "Email address for DTU alert notifications"
  type        = string
}

variable "docker_image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "vnet_address_space" {
  description = "VNet address space"
  type        = string
  default     = "10.0.0.0/16"
}

variable "web_subnet_prefix" {
  description = "Web app subnet prefix"
  type        = string
  default     = "10.0.1.0/24"
}

variable "api_subnet_prefix" {
  description = "API subnet prefix"
  type        = string
  default     = "10.0.2.0/24"
}

variable "gateway_subnet_prefix" {
  description = "App Gateway subnet prefix"
  type        = string
  default     = "10.0.3.0/24"
}