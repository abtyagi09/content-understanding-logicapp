param namePrefix string
param suffix string
param location string
param sku string
param integrationSubnetId string
param storageAccountName string
param contentShareName string
param contentUnderstandingEndpoint string
param contentUnderstandingAnalyzer string
param keyVaultUri string
param publicNetworkAccess bool
param tags object

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

var fileShareConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${namePrefix}-logic-plan'
  location: location
  kind: 'elastic'
  sku: {
    name: sku
    tier: 'WorkflowStandard'
  }
  tags: tags
  properties: {
    reserved: false
    maximumElasticWorkerCount: 2
  }
}

resource app 'Microsoft.Web/sites@2024-04-01' = {
  name: '${namePrefix}-logic-${suffix}'
  location: location
  kind: 'functionapp,workflowapp'
  identity: {
    type: 'SystemAssigned'
  }
  tags: tags
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    publicNetworkAccess: publicNetworkAccess ? 'Enabled' : 'Disabled'
    virtualNetworkSubnetId: integrationSubnetId
    vnetContentShareEnabled: true
    keyVaultReferenceIdentity: 'SystemAssigned'
    siteConfig: {
      alwaysOn: true
      netFrameworkVersion: 'v8.0'
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      // Private destinations use integration; public extension downloads retain App Service egress.
      vnetRouteAllEnabled: false
      appSettings: [
        {
          name: 'APP_KIND'
          value: 'workflowApp'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: fileShareConnectionString
        }
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storage.name
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AzureWebJobsStorage__credentialType'
          value: 'managedIdentity'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: contentShareName
        }
        // The share is pre-created; provisioning-time validation cannot reach private Storage.
        {
          name: 'WEBSITE_SKIP_CONTENTSHARE_VALIDATION'
          value: '1'
        }
        {
          name: 'WEBSITE_CONTENTOVERVNET'
          value: '1'
        }
        {
          name: 'WEBSITE_DNS_SERVER'
          value: '168.63.129.16'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~22'
        }
        {
          name: 'AZURE_STORAGE_ACCOUNT_NAME'
          value: storage.name
        }
        {
          name: 'AZURE_STORAGE_CONTAINER_NAME'
          value: 'documents'
        }
        {
          name: 'AZURE_STORAGE_RESULTS_CONTAINER_NAME'
          value: 'results'
        }
        {
          name: 'AZURE_STORAGE_BLOB_ENDPOINT'
          value: storage.properties.primaryEndpoints.blob
        }
        {
          name: 'CONTENT_UNDERSTANDING_ENDPOINT'
          value: contentUnderstandingEndpoint
        }
        {
          name: 'CONTENT_UNDERSTANDING_MODEL'
          value: contentUnderstandingAnalyzer
        }
        {
          name: 'KEY_VAULT_URI'
          value: keyVaultUri
        }
      ]
    }
  }
}

resource ftpPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: app
  name: 'ftp'
  properties: {
    allow: false
  }
}

resource scmPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: app
  name: 'scm'
  properties: {
    allow: false
  }
}

output name string = app.name
output url string = 'https://${app.properties.defaultHostName}'
output principalId string = app.identity.principalId
output resourceId string = app.id
