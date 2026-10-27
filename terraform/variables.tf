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

variable "logic_app_name_override" {
  description = "Optional explicit Logic App site name."
  type        = string
  default     = ""
}

variable "service_plan_name_override" {
  description = "Optional explicit App Service plan name."
  type        = string
  default     = ""
}

variable "storage_account_name_override" {
  description = "Optional explicit Storage account name."
  type        = string
  default     = ""
}

variable "user_assigned_identity_name_override" {
  description = "Optional explicit user-assigned managed identity name."
  type        = string
  default     = ""
}

variable "application_insights_name_override" {
  description = "Optional explicit Application Insights name."
  type        = string
  default     = ""
}

variable "existing_application_insights_id" {
  description = "Existing Application Insights resource ID to reuse."
  type        = string
  default     = ""
}

variable "existing_user_assigned_identity_id" {
  description = "Existing user-assigned managed identity resource ID to attach to the Logic App."
  type        = string
  default     = ""
}

variable "existing_storage_account_name" {
  description = "Existing storage account name to reuse for Logic App host storage. When set, Terraform does not create a new storage account."
  type        = string
  default     = ""
}

variable "log_analytics_workspace_name_override" {
  description = "Optional explicit Log Analytics workspace name when Terraform creates one."
  type        = string
  default     = ""
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

variable "existing_service_plan_id" {
  description = "Existing App Service plan resource ID. When set, Terraform reuses it instead of creating a new plan."
  type        = string
  default     = ""
}

variable "existing_vnet_id" {
  description = "Existing virtual network resource ID used for DNS links when reusing existing subnets."
  type        = string
  default     = ""
}

variable "existing_infra_subnet_id" {
  description = "Existing subnet resource ID for Logic App VNet integration. When set with existing_private_endpoint_subnet_id, no new VNet is created."
  type        = string
  default     = ""
}

variable "existing_private_endpoint_subnet_id" {
  description = "Existing subnet resource ID for private endpoints. When set with existing_infra_subnet_id, no new VNet is created."
  type        = string
  default     = ""
}

variable "existing_jumpbox_subnet_id" {
  description = "Existing subnet resource ID for jump box NIC when reusing an existing VNet."
  type        = string
  default     = ""
}

variable "existing_logicapp_private_dns_zone_id" {
  description = "Existing privatelink.azurewebsites.net private DNS zone resource ID. When set, Terraform reuses it."
  type        = string
  default     = ""
}

variable "existing_storage_private_dns_zone_ids" {
  description = "Existing storage private DNS zone IDs keyed by subresource (blob,file,queue,table). When all are provided, Terraform reuses them."
  type        = map(string)
  default     = {}
}

variable "logic_app_public_network_access" {
  description = "Keep public HTTPS ingress enabled. Set false to create a Logic App private endpoint and private App Service DNS zone."
  type        = bool
  default     = true
}

variable "create_logic_app_private_endpoint" {
  description = "Create a private endpoint for the Logic App when public network access is disabled."
  type        = bool
  default     = false
}

variable "content_understanding_analyzer" {
  description = "Analyzer ID used by the sample workflow."
  type        = string
  default     = "prebuilt-invoice"
}

variable "outlook_mailbox_user" {
  description = "Mailbox UPN/email polled by the ProcessOutlookInvoice workflow."
  type        = string
  default     = ""
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

variable "storage_network_default_action" {
  description = "Storage network rules default action."
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Allow", "Deny"], var.storage_network_default_action)
    error_message = "storage_network_default_action must be Allow or Deny."
  }
}

variable "content_share_name" {
  description = "Azure Files share name used by the Logic App host."
  type        = string
  default     = "logicapp-content"
}

variable "content_share_quota_gb" {
  description = "Azure Files share quota in GiB."
  type        = number
  default     = 100
}

variable "existing_log_analytics_workspace_id" {
  description = "Existing Log Analytics workspace resource ID. When set, Terraform uses this workspace for Application Insights."
  type        = string
  default     = ""
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

variable "create_data_plane_role_assignments" {
  description = "Create role assignments for Logic App and user-assigned identity."
  type        = bool
  default     = false
}
