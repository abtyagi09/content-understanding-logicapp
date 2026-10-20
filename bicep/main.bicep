targetScope = 'resourceGroup'

@description('Lowercase alphanumeric resource prefix. Use a new resource group for this replacement architecture.')
@minLength(3)
@maxLength(7)
param namePrefix string = 'cuapp'

@description('Region for the spoke and Logic Apps; when deployFoundry is true it must also support Content Understanding.')
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

@description('Create the private Azure AI Foundry account, Content Understanding project, endpoint, and role assignment.')
param deployFoundry bool = false

@allowed([
  'WS1'
  'WS2'
  'WS3'
])
param logicAppSku string = 'WS1'

@description('Allow public HTTPS ingress to the Logic App. When false, a private endpoint and private DNS zone are created.')
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
    contentUnderstandingEndpoint: deployFoundry
      ? 'https://${namePrefix}-ai-${suffix}.cognitiveservices.azure.com'
      : ''
    contentUnderstandingAnalyzer: contentUnderstandingAnalyzer
    keyVaultUri: services.outputs.keyVaultUri
    publicNetworkAccess: logicAppPublicNetworkAccess
    tags: tags
  }
}

module logicAppPrivateEndpoint './modules/private-endpoint.bicep' = if (!logicAppPublicNetworkAccess) {
  name: 'logic-app-private-endpoint'
  params: {
    name: '${namePrefix}-logicapp-pe'
    location: location
    subnetId: network.outputs.privateEndpointSubnetId
    vnetId: network.outputs.vnetId
    targetResourceId: logicApp.outputs.resourceId
    groupId: 'sites'
    privateDnsZoneNames: ['privatelink.azurewebsites.net']
    tags: tags
  }
}

module access './modules/access.bicep' = {
  name: 'logic-app-access'
  params: {
    principalId: logicApp.outputs.principalId
    storageAccountName: services.outputs.storageAccountName
    keyVaultName: services.outputs.keyVaultName
  }
}

module foundry './modules/foundry.bicep' = if (deployFoundry) {
  name: 'private-foundry'
  params: {
    namePrefix: namePrefix
    suffix: suffix
    location: location
    vnetId: network.outputs.vnetId
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    principalId: logicApp.outputs.principalId
    tags: tags
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
output logicAppPrivateEndpointName string = logicAppPrivateEndpoint.?outputs.endpointName ?? ''
output storageAccountName string = services.outputs.storageAccountName
output keyVaultName string = services.outputs.keyVaultName
output foundryAccountName string = foundry.?outputs.accountName ?? ''
output contentUnderstandingEndpoint string = foundry.?outputs.contentUnderstandingEndpoint ?? ''
output foundryProjectEndpoint string = foundry.?outputs.projectEndpoint ?? ''
output jumpboxName string = jumpbox.?outputs.name ?? ''
output jumpboxPrivateIp string = jumpbox.?outputs.privateIp ?? ''
