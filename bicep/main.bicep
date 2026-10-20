targetScope = 'resourceGroup'

@description('Lowercase alphanumeric resource prefix. Use a new resource group for this replacement architecture.')
@minLength(3)
@maxLength(7)
param namePrefix string = 'cuapp'

@description('Region for the spoke, Logic Apps, and Foundry. Must support Content Understanding and WS1.')
param location string = 'westus3'

param vnetAddressPrefix string = '10.50.0.0/16'
param infraSubnetPrefix string = '10.50.1.0/26'
param jumpboxSubnetPrefix string = '10.50.2.0/24'
param privateEndpointSubnetPrefix string = '10.50.3.0/24'

@description('SSH public key only; never supply a private key.')
@secure()
param adminSshPublicKey string = ''

@minLength(3)
@maxLength(20)
param adminUsername string = 'azureadmin'
param vmSize string = 'Standard_B2s'
@description('Create a private Ubuntu jump box. Requires an SSH public key and a customer-managed path into the VNet.')
param deployJumpbox bool = false

@description('Apply the SecurityControl=Ignore tag to the Storage account only. Use only when the customer has approved this policy exception.')
param azureFilesSharedKeyExceptionApproved bool = false

@allowed([
  'WS1'
  'WS2'
  'WS3'
])
param logicAppSku string = 'WS1'

@description('Allow HTTPS access to the Logic App and SCM endpoint. Storage, Key Vault, and Foundry remain private.')
param logicAppPublicNetworkAccess bool = true

@description('Analyzer to use after model deployments and Content Understanding defaults have been configured.')
param contentUnderstandingAnalyzer string = 'prebuilt-invoice'

param tags object = {
  environment: 'dev'
  project: 'content-understanding-spoke'
  managedBy: 'bicep'
}

var suffix = uniqueString(resourceGroup().id, namePrefix)

module network './modules/network.bicep' = {
  name: 'spoke-network'
  params: {
    namePrefix: namePrefix
    location: location
    vnetAddressPrefix: vnetAddressPrefix
    infraSubnetPrefix: infraSubnetPrefix
    jumpboxSubnetPrefix: jumpboxSubnetPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    tags: tags
  }
}

module services './modules/services.bicep' = {
  name: 'private-services'
  params: {
    namePrefix: namePrefix
    suffix: suffix
    location: location
    vnetId: network.outputs.vnetId
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    azureFilesSharedKeyExceptionApproved: azureFilesSharedKeyExceptionApproved
    tags: tags
  }
}

module logicApp './modules/logic-app.bicep' = {
  name: 'logic-app-standard'
  params: {
    namePrefix: namePrefix
    suffix: suffix
    location: location
    sku: logicAppSku
    integrationSubnetId: network.outputs.infraSubnetId
    storageAccountName: services.outputs.storageAccountName
    contentShareName: services.outputs.contentShareName
    contentUnderstandingEndpoint: services.outputs.contentUnderstandingEndpoint
    contentUnderstandingAnalyzer: contentUnderstandingAnalyzer
    keyVaultUri: services.outputs.keyVaultUri
    publicNetworkAccess: logicAppPublicNetworkAccess
    tags: tags
  }
}

module access './modules/access.bicep' = {
  name: 'logic-app-access'
  params: {
    principalId: logicApp.outputs.principalId
    storageAccountName: services.outputs.storageAccountName
    keyVaultName: services.outputs.keyVaultName
    foundryAccountName: services.outputs.foundryAccountName
  }
}

module jumpbox './modules/jumpbox.bicep' = if (deployJumpbox) {
  name: 'private-jumpbox'
  params: {
    namePrefix: namePrefix
    location: location
    subnetId: network.outputs.jumpboxSubnetId
    adminUsername: adminUsername
    adminSshPublicKey: adminSshPublicKey
    vmSize: vmSize
    tags: tags
  }
}

output vnetId string = network.outputs.vnetId
output logicAppName string = logicApp.outputs.name
output logicAppUrl string = logicApp.outputs.url
output logicAppPrincipalId string = logicApp.outputs.principalId
output storageAccountName string = services.outputs.storageAccountName
output keyVaultName string = services.outputs.keyVaultName
output foundryAccountName string = services.outputs.foundryAccountName
output contentUnderstandingEndpoint string = services.outputs.contentUnderstandingEndpoint
output foundryProjectEndpoint string = services.outputs.foundryProjectEndpoint
output jumpboxName string = jumpbox.?outputs.name ?? ''
output jumpboxPrivateIp string = jumpbox.?outputs.privateIp ?? ''
