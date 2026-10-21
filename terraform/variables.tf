variable "subscription_id" {
  description = "Azure subscription ID used by the AzureRM provider."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group in which to deploy the architecture."
  type        = string
}

variable "location" {
  description = "Optional region override. Null uses the resource group's region."
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Lowercase alphanumeric prefix used in resource names."
  type        = string
  default     = "cuapp"

  validation {
    condition     = can(regex("^[a-z0-9]{3,7}$", var.name_prefix))
    error_message = "name_prefix must contain 3-7 lowercase letters or digits."
  }
}

variable "vnet_address_prefix" {
  description = "IPv4 address space for the spoke VNet."
  type        = string
  default     = "10.50.0.0/16"
}

variable "infra_subnet_prefix" {
  description = "Address range for the Logic App integration subnet."
  type        = string
  default     = "10.50.1.0/26"
}

variable "jumpbox_subnet_prefix" {
  description = "Address range for the optional jump box subnet."
  type        = string
  default     = "10.50.2.0/24"
}

variable "private_endpoint_subnet_prefix" {
  description = "Address range for private endpoints."
  type        = string
  default     = "10.50.3.0/24"
}

variable "logic_app_sku" {
  description = "Workflow Standard SKU for the Logic App plan."
  type        = string
  default     = "WS1"

  validation {
    condition     = contains(["WS1", "WS2", "WS3"], var.logic_app_sku)
    error_message = "logic_app_sku must be one of WS1, WS2, or WS3."
  }
}

variable "logic_app_public_network_access" {
  description = "Keep public HTTPS ingress enabled. Set false to create a Logic App private endpoint and private App Service DNS zone."
  type        = bool
  default     = true
}

variable "content_understanding_analyzer" {
  description = "Analyzer ID used by the sample workflow."
  type        = string
  default     = "prebuilt-invoice"
}

variable "deploy_foundry" {
  description = "Create the private Foundry account, Content Understanding project, endpoint, and role assignment."
  type        = bool
  default     = false
}

variable "deploy_key_vault" {
  description = "Create a private Key Vault and related DNS/role assignment resources."
  type        = bool
  default     = false
}

variable "deploy_jumpbox" {
  description = "Create the optional private Ubuntu jump box."
  type        = bool
  default     = false
}

variable "admin_username" {
  description = "Jump box admin username."
  type        = string
  default     = "azureadmin"
}

variable "admin_ssh_public_key" {
  description = "SSH public key for the jump box. Required when deploy_jumpbox is true."
  type        = string
  default     = ""
  sensitive   = true
}

variable "vm_size" {
  description = "Jump box VM size."
  type        = string
  default     = "Standard_B2s"
}

variable "azure_files_shared_key_exception_approved" {
  description = "Apply SecurityControl=Ignore to the Storage account only when a customer-approved policy exception is required."
  type        = bool
  default     = false
}

variable "storage_dns_suffix" {
  description = "Storage DNS suffix for the selected Azure cloud."
  type        = string
  default     = "core.windows.net"
}

variable "tags" {
  description = "Additional resource tags."
  type        = map(string)
  default     = {}
}
