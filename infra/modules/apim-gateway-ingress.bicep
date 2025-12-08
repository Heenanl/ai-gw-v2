// https://learn.microsoft.com/azure/templates/microsoft.network/privateendpoints

@description('Location to be used for resources. Defaults to the resource group location')
param location string = resourceGroup().location

@description('The unique suffix to append. Defaults to a unique string based on subscription and resource group IDs.')
param resourceSuffix string = uniqueString(subscription().id, resourceGroup().id)

@description('APIM service resource ID to create the private endpoint for.')
param apimResourceId string

@description('APIM gateway URL (e.g., https://apim-name.azure-api.net) for backend configuration.')
param apimGatewayUrl string

@description('Subnet resource ID where the APIM gateway private endpoint will be deployed.')
param apimPeSubnetId string

@description('Subnet resource ID where the Application Gateway will be deployed.')
param appGwSubnetId string

@description('Private DNS zone resource ID for privatelink.azure-api.net.')
param privateDnsZoneId string

@description('Key Vault resource ID containing the TLS certificate.')
param keyVaultId string

@description('Name of the certificate secret in Key Vault.')
param certificateName string = 'appgw-cert'

@description('User-assigned managed identity resource ID with Key Vault Secrets User role.')
param managedIdentityId string

@description('Tags to apply to all resources.')
param tags object = {}


// ------------------------------
//    VARIABLES
// ------------------------------

// Extract hostname from APIM gateway URL (remove https:// prefix)
var apimGatewayHostname = replace(apimGatewayUrl, 'https://', '')


// ------------------------------
//    RESOURCES
// ------------------------------

// First deploy APIM gateway private endpoint
module apimGatewayPE 'apim-gateway-private-endpoint.bicep' = {
  name: 'deploy-apim-gateway-pe-nested'
  params: {
    location: location
    resourceSuffix: resourceSuffix
    apimResourceId: apimResourceId
    subnetId: apimPeSubnetId
    privateDnsZoneId: privateDnsZoneId
    tags: tags
  }
}

// Then deploy Application Gateway with the APIM hostname
module appGateway 'app-gateway.bicep' = {
  name: 'deploy-app-gateway-nested'
  params: {
    location: location
    resourceSuffix: resourceSuffix
    subnetId: appGwSubnetId
    apimGatewayHostname: apimGatewayHostname
    keyVaultId: keyVaultId
    certificateName: certificateName
    managedIdentityId: managedIdentityId
    tags: tags
  }
}


// ------------------------------
//    OUTPUTS
// ------------------------------

@description('APIM gateway private endpoint resource ID.')
output apimPeId string = apimGatewayPE.outputs.privateEndpointId

@description('APIM gateway private endpoint name.')
output apimPeName string = apimGatewayPE.outputs.privateEndpointName

@description('Application Gateway resource ID.')
output appGatewayId string = appGateway.outputs.applicationGatewayId

@description('Application Gateway name.')
output appGatewayName string = appGateway.outputs.applicationGatewayName

@description('Public IP address FQDN.')
output appGatewayPublicFqdn string = appGateway.outputs.publicIpFqdn

@description('Public IP address.')
output appGatewayPublicIp string = appGateway.outputs.publicIpAddress
