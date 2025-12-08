// https://learn.microsoft.com/azure/templates/microsoft.network/privateendpoints

@description('Location to be used for resources. Defaults to the resource group location')
param location string = resourceGroup().location

@description('The unique suffix to append. Defaults to a unique string based on subscription and resource group IDs.')
param resourceSuffix string = uniqueString(subscription().id, resourceGroup().id)

@description('APIM service resource ID to create the private endpoint for.')
param apimResourceId string

@description('Subnet resource ID where the APIM gateway private endpoint will be deployed.')
param subnetId string

@description('Private DNS zone resource ID for privatelink.azure-api.net.')
param privateDnsZoneId string

@description('Tags to apply to all resources.')
param tags object = {}


// ------------------------------
//    RESOURCES
// ------------------------------

// https://learn.microsoft.com/azure/templates/microsoft.network/privateendpoints
resource apimGatewayPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pep-apim-gateway-${resourceSuffix}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'apim-gateway-connection'
        properties: {
          privateLinkServiceId: apimResourceId
          groupIds: [
            'Gateway'
          ]
        }
      }
    ]
  }
}

// https://learn.microsoft.com/azure/templates/microsoft.network/privateendpoints/privatednszonegroups
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: apimGatewayPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'apim-gateway-dns-config'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}


// ------------------------------
//    OUTPUTS
// ------------------------------

@description('APIM gateway private endpoint resource ID.')
output privateEndpointId string = apimGatewayPrivateEndpoint.id

@description('APIM gateway private endpoint name.')
output privateEndpointName string = apimGatewayPrivateEndpoint.name
