@description('Location to deploy networking resources. Defaults to resource group location.')
param location string = resourceGroup().location

@description('Virtual network name. When createNewVnet=false this VNet must already exist in the same resource group.')
param vnetName string

@description('Address space CIDR prefixes used when creating a new VNet.')
param vnetAddressPrefixes array = ['10.50.0.0/20']

@description('Set to true to create the virtual network and subnets; set to false to reference an existing VNet.')
param createNewVnet bool = true

@description('Dedicated APIM subnet name (exclusive use).')
param apimSubnetName string = 'snet-apim'

@description('Dedicated APIM subnet CIDR prefix (minimum /27).')
param apimSubnetPrefix string

@description('Private endpoint subnet name.')
param pepSubnetName string = 'snet-pep-ai'

@description('Private endpoint subnet CIDR prefix.')
param pepSubnetPrefix string

@description('Private endpoint IPs to allow for Cognitive Services egress; leave empty to use CognitiveServices service tag (Phase 1).')
param allowedCognitivePrivateEndpointIps array = []

@description('Tags applied to created resources.')
param tags object = {}

// ------------------------------
//    VARIABLES
// ------------------------------
var cognitiveRule = length(allowedCognitivePrivateEndpointIps) == 0 ? {
  name: 'allow-cognitive-services-outbound'
  properties: {
    description: 'Phase 1: Allow outbound to Cognitive Services via service tag'
    protocol: 'Tcp'
    sourcePortRange: '*'
    destinationPortRange: '443'
    sourceAddressPrefix: 'VirtualNetwork'
    destinationAddressPrefix: 'CognitiveServicesFrontend'
    access: 'Allow'
    priority: 120
    direction: 'Outbound'
  }
} : {
  name: 'allow-cognitive-private-outbound'
  properties: {
    description: 'Phase 2: Restrict outbound to private endpoint IPs'
    protocol: 'Tcp'
    sourcePortRange: '*'
    destinationPortRange: '443'
    sourceAddressPrefix: 'VirtualNetwork'
    destinationAddressPrefixes: allowedCognitivePrivateEndpointIps
    access: 'Allow'
    priority: 120
    direction: 'Outbound'
  }
}

// ------------------------------
//    RESOURCES
// ------------------------------
resource nsgApim 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${apimSubnetName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow-storage-outbound'
        properties: {
          description: 'APIM dependency on Azure Storage'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Storage'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'allow-azuremonitor-outbound'
        properties: {
          description: 'Telemetry to Azure Monitor / Application Insights'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureMonitor'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
      cognitiveRule
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = if (createNewVnet) {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: vnetAddressPrefixes
    }
  }
}

resource existingVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = if (!createNewVnet) {
  name: vnetName
}

resource apimSubnetNew 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = if (createNewVnet) {
  parent: vnet
  name: apimSubnetName
  properties: {
    addressPrefix: apimSubnetPrefix
    delegations: [
      {
        name: 'apimDelegation'
        properties: {
          serviceName: 'Microsoft.Web/serverFarms'
        }
      }
    ]
    networkSecurityGroup: {
      id: nsgApim.id
    }
  }
}

resource apimSubnetExisting 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = if (!createNewVnet) {
  parent: existingVnet
  name: apimSubnetName
  properties: {
    addressPrefix: apimSubnetPrefix
    delegations: [
      {
        name: 'apimDelegation'
        properties: {
          serviceName: 'Microsoft.Web/serverFarms'
        }
      }
    ]
    networkSecurityGroup: {
      id: nsgApim.id
    }
  }
}

resource pepSubnetNew 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = if (createNewVnet) {
  parent: vnet
  name: pepSubnetName
  properties: {
    addressPrefix: pepSubnetPrefix
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

resource pepSubnetExisting 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = if (!createNewVnet) {
  parent: existingVnet
  name: pepSubnetName
  properties: {
    addressPrefix: pepSubnetPrefix
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.cognitiveservices.azure.com'
  location: 'global'
  tags: tags
}

resource dnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: createNewVnet ? vnet.id : resourceId('Microsoft.Network/virtualNetworks', vnetName)
    }
    registrationEnabled: false
  }
}

// ------------------------------
//    OUTPUTS
// ------------------------------
var apimSubnetResourceId = createNewVnet ? apimSubnetNew.id : apimSubnetExisting.id
var pepSubnetResourceId = createNewVnet ? pepSubnetNew.id : pepSubnetExisting.id

@description('APIM delegated subnet resource ID.')
output apimSubnetId string = apimSubnetResourceId

@description('Private endpoint subnet resource ID.')
output pepSubnetId string = pepSubnetResourceId

@description('Network security group resource ID applied to the APIM subnet.')
output apimSubnetNsgId string = nsgApim.id

@description('Private DNS zone resource ID for Cognitive Services.')
output privateDnsZoneId string = privateDnsZone.id

@description('Virtual network resource ID (created or referenced).')
output vnetId string = resourceId('Microsoft.Network/virtualNetworks', vnetName)
