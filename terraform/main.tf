terraform {
  required_version = ">= 1.11.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "azapi" {}

data "azurerm_resource_group" "current" {
  name = var.resource_group_name
}

data "azurerm_client_config" "current" {}

locals {
  location = coalesce(var.location, data.azurerm_resource_group.current.location)
  suffix   = substr(sha1(data.azurerm_resource_group.current.id), 0, 13)

  storage_account_name = substr(replace(lower("${var.name_prefix}${local.suffix}"), "-", ""), 0, 24)
  key_vault_name       = "${var.name_prefix}-kv-${local.suffix}"
  logic_app_name       = "${var.name_prefix}-logic-${local.suffix}"
  foundry_name         = "${var.name_prefix}-ai-${local.suffix}"

  content_share_name = "logicapp-content"

  common_tags = merge({
    environment = "dev"
    managedBy   = "terraform"
    project     = "content-understanding-spoke"
  }, var.tags)

  storage_tags = var.azure_files_shared_key_exception_approved ? merge(local.common_tags, {
    SecurityControl = "Ignore"
  }) : local.common_tags

  storage_private_dns_zones = {
    blob  = "privatelink.blob.${var.storage_dns_suffix}"
    file  = "privatelink.file.${var.storage_dns_suffix}"
    queue = "privatelink.queue.${var.storage_dns_suffix}"
    table = "privatelink.table.${var.storage_dns_suffix}"
  }
}

resource "azurerm_network_security_group" "jumpbox" {
  count               = var.deploy_jumpbox ? 1 : 0
  name                = "${var.name_prefix}-jumpbox-nsg"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.current.name
  tags                = local.common_tags

  security_rule {
    name                       = "AllowSshFromSpoke"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.vnet_address_prefix
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyOtherInbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

module "vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.8.1"

  enable_telemetry = false
  name             = "${var.name_prefix}-vnet"
  location         = local.location
  resource_group_name = data.azurerm_resource_group.current.name
  address_space    = [var.vnet_address_prefix]
  tags             = local.common_tags

  subnets = {
    infra = {
      name                            = "snet-infra"
      address_prefixes                = [var.infra_subnet_prefix]
      default_outbound_access_enabled = false
      delegation = [
        {
          name = "logic-app-integration"
          service_delegation = {
            name = "Microsoft.Web/serverFarms"
          }
        }
      ]
    }
    jumpbox = {
      name                            = "snet-jumpbox"
      address_prefixes                = [var.jumpbox_subnet_prefix]
      default_outbound_access_enabled = false
      network_security_group = var.deploy_jumpbox ? {
        id = azurerm_network_security_group.jumpbox[0].id
      } : null
    }
    private_endpoints = {
      name                                          = "snet-private-endpoints"
      address_prefixes                              = [var.private_endpoint_subnet_prefix]
      default_outbound_access_enabled               = false
      private_endpoint_network_policies             = "Disabled"
      private_link_service_network_policies_enabled = false
    }
  }
}

module "storage_dns_zone" {
  for_each = local.storage_private_dns_zones
  source   = "Azure/avm-res-network-privatednszone/azurerm"
  version  = "0.4.3"

  enable_telemetry = false
  domain_name      = each.value
  parent_id        = data.azurerm_resource_group.current.id
  tags             = local.common_tags

  virtual_network_links = {
    spoke = {
      name                 = "${var.name_prefix}-storage-${each.key}-vnet-link"
      virtual_network_id   = module.vnet.resource_id
      registration_enabled = false
    }
  }
}

module "keyvault_dns_zone" {
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.4.3"

  enable_telemetry = false
  domain_name      = "privatelink.vaultcore.azure.net"
  parent_id        = data.azurerm_resource_group.current.id
  tags             = local.common_tags

  virtual_network_links = {
    spoke = {
      name                 = "${var.name_prefix}-keyvault-vnet-link"
      virtual_network_id   = module.vnet.resource_id
      registration_enabled = false
    }
  }
}

module "logicapp_dns_zone" {
  count   = var.logic_app_public_network_access ? 0 : 1
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.4.3"

  enable_telemetry = false
  domain_name      = "privatelink.azurewebsites.net"
  parent_id        = data.azurerm_resource_group.current.id
  tags             = local.common_tags

  virtual_network_links = {
    spoke = {
      name                 = "${var.name_prefix}-logicapp-pe-vnet-link"
      virtual_network_id   = module.vnet.resource_id
      registration_enabled = false
    }
  }
}

module "storage" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.10.0"

  enable_telemetry = false
  name             = local.storage_account_name
  location         = local.location
  parent_id        = data.azurerm_resource_group.current.id
  tags             = local.storage_tags

  account_kind                     = "StorageV2"
  account_sku_name                 = "Standard_LRS"
  min_tls_version                  = "TLS1_2"
  public_network_access_enabled    = false
  shared_access_key_enabled        = true
  cross_tenant_replication_enabled = false

  network_rules = {
    default_action = "Deny"
    bypass         = ["None"]
  }

  shares = {
    content = {
      name  = local.content_share_name
      quota = 100
    }
  }

  containers = {
    documents = {
      name = "documents"
    }
    results = {
      name = "results"
    }
  }

  private_endpoints = {
    for subresource in ["blob", "file", "queue", "table"] :
    subresource => {
      name                        = "${var.name_prefix}-storage-${subresource}-pe"
      subnet_resource_id          = module.vnet.subnets["private_endpoints"].resource_id
      subresource_name            = subresource
      private_dns_zone_group_name = "default"
      private_dns_zone_resource_ids = toset([
        module.storage_dns_zone[subresource].resource_id
      ])
    }
  }
}

module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.12.0"

  enable_telemetry = false
  name             = local.key_vault_name
  location         = local.location
  resource_group_name = data.azurerm_resource_group.current.name
  tenant_id        = data.azurerm_client_config.current.tenant_id
  tags             = local.common_tags

  legacy_access_policies_enabled = false
  public_network_access_enabled  = false
  purge_protection_enabled       = true

  network_acls = {
    bypass                     = "None"
    default_action             = "Deny"
    ip_rules                   = []
    virtual_network_subnet_ids = []
  }

  private_endpoints = {
    default = {
      name                        = "${var.name_prefix}-keyvault-pe"
      subnet_resource_id          = module.vnet.subnets["private_endpoints"].resource_id
      subresource_name            = "vault"
      private_dns_zone_group_name = "default"
      private_dns_zone_resource_ids = toset([
        module.keyvault_dns_zone.resource_id
      ])
    }
  }
}

resource "azapi_resource_action" "storage_list_keys" {
  type                   = "Microsoft.Storage/storageAccounts@2024-01-01"
  resource_id            = module.storage.resource_id
  action                 = "listKeys"
  method                 = "POST"
  response_export_values = ["keys"]
}

resource "azurerm_service_plan" "logic" {
  name                = "${var.name_prefix}-logic-plan"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.current.name
  os_type             = "Windows"
  sku_name            = var.logic_app_sku
  worker_count        = 1
  tags                = local.common_tags
}

resource "azurerm_logic_app_standard" "logic" {
  name                       = local.logic_app_name
  location                   = local.location
  resource_group_name        = data.azurerm_resource_group.current.name
  app_service_plan_id        = azurerm_service_plan.logic.id
  storage_account_name       = module.storage.name
  storage_account_access_key = azapi_resource_action.storage_list_keys.output.keys[0].value
  version                    = "~4"
  https_only                 = true
  virtual_network_subnet_id  = module.vnet.subnets["infra"].resource_id
  tags                       = local.common_tags

  identity {
    type = "SystemAssigned"
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME             = "node"
    WEBSITE_NODE_DEFAULT_VERSION         = "~22"
    WEBSITE_SKIP_CONTENTSHARE_VALIDATION = "1"
    WEBSITE_CONTENTOVERVNET              = "1"
    WEBSITE_DNS_SERVER                   = "168.63.129.16"
    AzureWebJobsStorage__accountName     = module.storage.name
    AzureWebJobsStorage__credential      = "managedidentity"
    AzureWebJobsStorage__credentialType  = "managedIdentity"
    AZURE_STORAGE_ACCOUNT_NAME           = module.storage.name
    AZURE_STORAGE_CONTAINER_NAME         = module.storage.containers["documents"].name
    AZURE_STORAGE_RESULTS_CONTAINER_NAME = module.storage.containers["results"].name
    AZURE_STORAGE_BLOB_ENDPOINT          = "https://${module.storage.fqdn.blob}"
    CONTENT_UNDERSTANDING_ENDPOINT       = var.deploy_foundry ? "https://${local.foundry_name}.cognitiveservices.azure.com" : ""
    CONTENT_UNDERSTANDING_MODEL          = var.content_understanding_analyzer
    KEY_VAULT_URI                        = module.key_vault.uri
  }

  site_config {
    always_on                 = true
    ftps_state                = "Disabled"
    use_32_bit_worker_process = false
  }
}

resource "azapi_update_resource" "logic_site_network_config" {
  type      = "Microsoft.Web/sites@2024-04-01"
  name      = azurerm_logic_app_standard.logic.name
  parent_id = data.azurerm_resource_group.current.id

  body = {
    properties = {
      publicNetworkAccess       = var.logic_app_public_network_access ? "Enabled" : "Disabled"
      keyVaultReferenceIdentity = "SystemAssigned"
      vnetContentShareEnabled   = true
      siteConfig = {
        scmMinTlsVersion    = "1.2"
        vnetRouteAllEnabled = false
      }
    }
  }
}

module "logic_app_private_endpoint" {
  count   = var.logic_app_public_network_access ? 0 : 1
  source  = "Azure/avm-res-network-privateendpoint/azurerm"
  version = "0.2.0"

  location                        = local.location
  name                            = "${var.name_prefix}-logicapp-pe"
  network_interface_name          = "${var.name_prefix}-logicapp-pe-nic"
  resource_group_name             = data.azurerm_resource_group.current.name
  subnet_resource_id              = module.vnet.subnets["private_endpoints"].resource_id
  private_connection_resource_id  = azurerm_logic_app_standard.logic.id
  subresource_names               = ["sites"]
  private_service_connection_name = "${var.name_prefix}-logicapp-pe-connection"
  private_dns_zone_group_name     = "default"
  private_dns_zone_resource_ids   = [module.logicapp_dns_zone[0].resource_id]
  tags                            = local.common_tags
}

resource "azapi_resource" "foundry" {
  count     = var.deploy_foundry ? 1 : 0
  type      = "Microsoft.CognitiveServices/accounts@2025-06-01"
  name      = local.foundry_name
  parent_id = data.azurerm_resource_group.current.id
  location  = local.location
  tags      = local.common_tags
  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "AIServices"
    sku = {
      name = "S0"
    }
    properties = {
      customSubDomainName    = local.foundry_name
      allowProjectManagement = true
      disableLocalAuth       = true
      publicNetworkAccess    = "Disabled"
      networkAcls = {
        defaultAction       = "Deny"
        ipRules             = []
        virtualNetworkRules = []
      }
    }
  }
}

resource "azapi_resource" "foundry_project" {
  count     = var.deploy_foundry ? 1 : 0
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name      = "content-understanding"
  parent_id = azapi_resource.foundry[0].id
  location  = local.location
  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      displayName = "Content Understanding"
      description = "Private document processing with Logic Apps Standard."
    }
  }
}

module "foundry_dns_zone" {
  for_each = var.deploy_foundry ? {
    cognitive = "privatelink.cognitiveservices.azure.com"
    openai    = "privatelink.openai.azure.com"
    services  = "privatelink.services.ai.azure.com"
  } : {}
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.4.3"

  enable_telemetry = false
  domain_name      = each.value
  parent_id        = data.azurerm_resource_group.current.id
  tags             = local.common_tags

  virtual_network_links = {
    spoke = {
      name                 = "${var.name_prefix}-foundry-${each.key}-vnet-link"
      virtual_network_id   = module.vnet.resource_id
      registration_enabled = false
    }
  }
}

module "foundry_private_endpoint" {
  count   = var.deploy_foundry ? 1 : 0
  source  = "Azure/avm-res-network-privateendpoint/azurerm"
  version = "0.2.0"

  location                        = local.location
  name                            = "${var.name_prefix}-foundry-pe"
  network_interface_name          = "${var.name_prefix}-foundry-pe-nic"
  resource_group_name             = data.azurerm_resource_group.current.name
  subnet_resource_id              = module.vnet.subnets["private_endpoints"].resource_id
  private_connection_resource_id  = azapi_resource.foundry[0].id
  subresource_names               = ["account"]
  private_service_connection_name = "${var.name_prefix}-foundry-pe-connection"
  private_dns_zone_group_name     = "default"
  private_dns_zone_resource_ids   = [for z in module.foundry_dns_zone : z.resource_id]
  tags                            = local.common_tags
}

resource "azurerm_role_assignment" "logic_storage_blob" {
  scope                = module.storage.resource_id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_logic_app_standard.logic.identity[0].principal_id
}

resource "azurerm_role_assignment" "logic_storage_queue" {
  scope                = module.storage.resource_id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_logic_app_standard.logic.identity[0].principal_id
}

resource "azurerm_role_assignment" "logic_storage_table" {
  scope                = module.storage.resource_id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_logic_app_standard.logic.identity[0].principal_id
}

resource "azurerm_role_assignment" "logic_key_vault" {
  scope                = module.key_vault.resource_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_logic_app_standard.logic.identity[0].principal_id
}

resource "azurerm_role_assignment" "logic_foundry" {
  count                = var.deploy_foundry ? 1 : 0
  scope                = azapi_resource.foundry[0].id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_logic_app_standard.logic.identity[0].principal_id
}

resource "azurerm_network_interface" "jumpbox" {
  count               = var.deploy_jumpbox ? 1 : 0
  name                = "${var.name_prefix}-jumpbox-nic"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.current.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "private"
    subnet_id                     = module.vnet.subnets["jumpbox"].resource_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "jumpbox" {
  count                           = var.deploy_jumpbox ? 1 : 0
  name                            = "${var.name_prefix}-jumpbox"
  computer_name                   = "${var.name_prefix}-jumpbox"
  location                        = local.location
  resource_group_name             = data.azurerm_resource_group.current.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.jumpbox[0].id]
  tags                            = local.common_tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  identity {
    type = "SystemAssigned"
  }
}
