using './main.bicep'

param namePrefix = 'cuapp'
param location = 'westus3'
param vnetAddressPrefix = '10.50.0.0/16'
param infraSubnetPrefix = '10.50.1.0/26'
param jumpboxSubnetPrefix = '10.50.2.0/24'
param privateEndpointSubnetPrefix = '10.50.3.0/24'
param adminUsername = 'azureadmin'
param adminSshPublicKey = readEnvironmentVariable('JUMPBOX_SSH_PUBLIC_KEY', '')
param vmSize = 'Standard_B2s'
param logicAppSku = 'WS1'
param logicAppPublicNetworkAccess = true
param contentUnderstandingAnalyzer = 'prebuilt-invoice'
param deployJumpbox = false
param azureFilesSharedKeyExceptionApproved = false
