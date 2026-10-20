param namePrefix string
param suffix string
param location string
param vnetId string
param privateEndpointSubnetId string
param azureFilesSharedKeyExceptionApproved bool
param tags object

var contentShareName = 'logicapp-content'
var storageServices = ['blob', 'file', 'queue', 'table']
var storageTags = azureFilesSharedKeyExceptionApproved ? union(tags, {
  // Customer-approved exception for the Azure Files content share only.
  SecurityControl: 'Ignore'
}) : tags

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: '${namePrefix}${suffix}'
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  tags: storageTags
  properties: {
    // Windows Logic Apps Standard mounts Azure Files using this account's key.
    allowSharedKeyAccess: true
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
    }
  }
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {}
}

resource contentShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  parent: fileService
  name: contentShareName
  properties: {
    shareQuota: 100
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {}
}

resource documents 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'documents'
  properties: {
    publicAccess: 'None'
  }
}

resource results 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'results'
  properties: {
    publicAccess: 'None'
  }
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: '${namePrefix}-kv-${suffix}'
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 90
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
    }
  }
}

module storageEndpoints './private-endpoint.bicep' = [for service in storageServices: {
  name: 'storage-${service}-endpoint'
  params: {
    name: '${namePrefix}-storage-${service}-pe'
    location: location
    subnetId: privateEndpointSubnetId
    vnetId: vnetId
    targetResourceId: storage.id
    groupId: service
    privateDnsZoneNames: ['privatelink.${service}.${environment().suffixes.storage}']
    tags: tags
  }
}]

module vaultEndpoint './private-endpoint.bicep' = {
  name: 'keyvault-endpoint'
  params: {
    name: '${namePrefix}-keyvault-pe'
    location: location
    subnetId: privateEndpointSubnetId
    vnetId: vnetId
    targetResourceId: vault.id
    groupId: 'vault'
    privateDnsZoneNames: ['privatelink.vaultcore.azure.net']
    tags: tags
  }
}

output storageAccountName string = storage.name
output contentShareName string = contentShare.name
output keyVaultName string = vault.name
output keyVaultUri string = vault.properties.vaultUri
