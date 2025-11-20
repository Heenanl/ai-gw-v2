@description('AI Foundry account definitions including name and resource ID.')
param accounts array

@description('Private endpoint subnet resource ID.')
param pepSubnetId string

@description('Location for private endpoints. Defaults to resource group location.')
param location string = resourceGroup().location

@description('Private DNS zone resource ID for Cognitive Services.')
param privateDnsZoneId string

@description('Tags to apply to private endpoint resources.')
param tags object = {}

// ------------------------------
//    RESOURCES
// ------------------------------
@batchSize(1)
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = [for (account, i) in accounts: {
  name: 'pep-${account.name}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: pepSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'cogsvc'
        properties: {
          privateLinkServiceId: account.id
          groupIds: [
            'account'
          ]
          requestMessage: 'Private access from APIM to Azure AI Foundry account'
        }
      }
    ]
  }
}]

@batchSize(1)
resource privateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = [for (account, i) in accounts: {
  parent: privateEndpoint[i]
  name: 'pdzg-cognitiveservices'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}]
