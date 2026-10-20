param namePrefix string
param suffix string
param location string
param vnetId string
param privateEndpointSubnetId string
param principalId string
param tags object

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: '${namePrefix}-ai-${suffix}'
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  tags: tags
  properties: {
    customSubDomainName: '${namePrefix}-ai-${suffix}'
    allowProjectManagement: true
    disableLocalAuth: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: foundry
  name: 'content-understanding'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'Content Understanding'
    description: 'Private document processing with Logic Apps Standard.'
  }
}

module endpoint './private-endpoint.bicep' = {
  name: 'foundry-endpoint'
  params: {
    name: '${namePrefix}-foundry-pe'
    location: location
    subnetId: privateEndpointSubnetId
    vnetId: vnetId
    targetResourceId: foundry.id
    groupId: 'account'
    privateDnsZoneNames: [
      'privatelink.cognitiveservices.azure.com'
      'privatelink.openai.azure.com'
      'privatelink.services.ai.azure.com'
    ]
    tags: tags
  }
}

resource foundryAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, principalId, 'cognitive-services-user')
  scope: foundry
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')
  }
}

output accountName string = foundry.name
// Content Understanding uses the account endpoint, not the Foundry project API endpoint.
output contentUnderstandingEndpoint string = 'https://${foundry.name}.cognitiveservices.azure.com'
output projectEndpoint string = 'https://${foundry.name}.services.ai.azure.com/api/projects/${project.name}'
