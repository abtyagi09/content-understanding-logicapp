param name string
param location string
param subnetId string
param vnetId string
param targetResourceId string
param groupId string
param privateDnsZoneNames array
param tags object

resource zones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for zoneName in privateDnsZoneNames: {
  name: zoneName
  location: 'global'
  tags: tags
}]

resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zoneName, i) in privateDnsZoneNames: {
  parent: zones[i]
  name: '${name}-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}]

resource endpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${name}-connection'
        properties: {
          privateLinkServiceId: targetResourceId
          groupIds: [groupId]
        }
      }
    ]
  }
}

resource dnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: endpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for (zoneName, i) in privateDnsZoneNames: {
      name: 'zone-${i}'
      properties: {
        privateDnsZoneId: zones[i].id
      }
    }]
  }
}
