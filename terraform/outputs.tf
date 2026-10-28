output "vnet_id" {
  description = "Resource ID of the spoke VNet."
  value       = module.vnet.resource_id
}

output "logic_app_name" {
  description = "Name of the Logic App Standard site."
  value       = azurerm_logic_app_standard.logic.name
}

output "logic_app_url" {
  description = "Public hostname for the Logic App site."
  value       = "https://${azurerm_logic_app_standard.logic.default_hostname}"
}

output "logic_app_principal_id" {
  description = "System-assigned managed identity principal ID for the Logic App."
  value       = azurerm_logic_app_standard.logic.identity[0].principal_id
}

output "logic_app_private_endpoint_name" {
  description = "Private endpoint name for inbound Logic App access when public ingress is disabled."
  value       = var.logic_app_public_network_access ? "" : module.logic_app_private_endpoint[0].name
}

output "storage_account_name" {
  description = "Name of the private Storage account."
  value       = local.storage_account_name
}

output "logic_app_user_assigned_identity_id" {
  description = "Resource ID of the user-assigned managed identity attached to the Logic App."
  value       = azurerm_user_assigned_identity.logic_uami.id
}

output "application_insights_name" {
  description = "Application Insights resource name for the Logic App."
  value       = azurerm_application_insights.logic.name
}

output "key_vault_name" {
  description = "Name of the private Key Vault."
  value       = var.deploy_key_vault ? module.key_vault[0].name : ""
}

output "foundry_account_name" {
  description = "Foundry account name when deploy_foundry is enabled."
  value       = var.deploy_foundry ? azapi_resource.foundry[0].name : ""
}

output "content_understanding_endpoint" {
  description = "Content Understanding endpoint when deploy_foundry is enabled."
  value       = var.deploy_foundry ? "https://${azapi_resource.foundry[0].name}.cognitiveservices.azure.com" : ""
}

output "foundry_project_endpoint" {
  description = "Foundry project endpoint when deploy_foundry is enabled."
  value       = var.deploy_foundry ? "https://${azapi_resource.foundry[0].name}.services.ai.azure.com/api/projects/${azapi_resource.foundry_project[0].name}" : ""
}

output "content_understanding_completion_deployment_name" {
  description = "Name of the chat completion model deployment used by Content Understanding analyzers, when deploy_foundry is enabled."
  value       = var.deploy_foundry ? azurerm_cognitive_deployment.content_understanding_completion[0].name : ""
}

output "content_understanding_embedding_deployment_name" {
  description = "Name of the embedding model deployment used by Content Understanding analyzers, when deploy_foundry is enabled."
  value       = var.deploy_foundry ? azurerm_cognitive_deployment.content_understanding_embedding[0].name : ""
}

output "outlook_graph_permissions_granted" {
  description = "Whether Microsoft Graph Mail.ReadWrite was granted to the Logic App's identities."
  value       = var.grant_outlook_graph_permissions
}

output "jumpbox_name" {
  description = "Jump box VM name when deploy_jumpbox is enabled."
  value       = var.deploy_jumpbox ? azurerm_linux_virtual_machine.jumpbox[0].name : ""
}

output "jumpbox_private_ip" {
  description = "Jump box private IP address when deploy_jumpbox is enabled."
  value       = var.deploy_jumpbox ? azurerm_network_interface.jumpbox[0].private_ip_address : ""
}
