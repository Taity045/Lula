variable "resource_group_name" {
  type        = string
  description = "Resource group for the orders service."
}

variable "location" {
  type        = string
  description = "Azure region."
  default     = "southafricanorth"
}

variable "environment" {
  type        = string
  description = "Environment name."
  default     = "dev"
}

variable "container_image" {
  type        = string
  description = "Published orders API image, preferably pinned by digest."
}

variable "app_subnet_id" {
  type        = string
  description = "Existing subnet reserved for the Container Apps environment."
}

variable "database_subnet_id" {
  type        = string
  description = "Existing subnet delegated to PostgreSQL Flexible Server."
}

variable "database_private_dns_zone_id" {
  type        = string
  description = "PostgreSQL private DNS zone already linked to the application network."
}

variable "database_server_name" {
  type        = string
  description = "Globally unique PostgreSQL server name."
}

variable "database_admin_password" {
  type        = string
  description = "Database administrator password supplied securely at deployment."
  sensitive   = true
}

variable "key_vault_name" {
  type        = string
  description = "Globally unique Key Vault name."
}

variable "min_replicas" {
  type        = number
  description = "Minimum application replicas. Zero allows development scale-to-zero."
  default     = 0
}

variable "max_replicas" {
  type        = number
  description = "Maximum application replicas."
  default     = 2
}

variable "deploy_app" {
  type        = bool
  description = "Enable after the database is initialized and orders-db-url exists in Key Vault."
  default     = false
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Existing workspace for application logs."
}
