variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "project_name" {
  description = "Project name prefix for resource naming"
  type        = string
  default     = "indexer-demo"
}

variable "project_name_short" {
  description = "Short project name for storage accounts (max 10 chars, lowercase alphanumeric only)"
  type        = string
  default     = "idxdemo"

  validation {
    condition     = can(regex("^[a-z0-9]{1,10}$", var.project_name_short))
    error_message = "project_name_short must be 1-10 lowercase alphanumeric characters."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-indexer-demo"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "westus"
}

variable "storage_container_name" {
  description = "Name of the blob container for documents"
  type        = string
  default     = "documents"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    project     = "indexer-demo"
    environment = "dev"
  }
}

# variable "allowed_ip_address" {
#   description = "IP address (CIDR) allowed to access Function App and Backend"
#   type        = string
#   default     = "0.0.0.0/32"
# }
