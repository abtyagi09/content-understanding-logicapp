param namePrefix string
param location string
param vnetAddressPrefix string
param infraSubnetPrefix string
param jumpboxSubnetPrefix string
param privateEndpointSubnetPrefix string
param tags object

resource jumpboxNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${namePrefix}-jumpbox-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowSshFromSpoke'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: vnetAddressPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'DenyOtherInbound'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${namePrefix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: 'snet-infra'
        properties: {
          addressPrefix: infraSubnetPrefix
          defaultOutboundAccess: false
          delegations: [
            {
              name: 'logic-app-integration'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'snet-jumpbox'
        properties: {
          addressPrefix: jumpboxSubnetPrefix
          defaultOutboundAccess: false
          networkSecurityGroup: {
            id: jumpboxNsg.id
          }
        }
      }
      {
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          defaultOutboundAccess: false
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output infraSubnetId string = vnet.properties.subnets[0].id
output jumpboxSubnetId string = vnet.properties.subnets[1].id
output privateEndpointSubnetId string = vnet.properties.subnets[2].id
