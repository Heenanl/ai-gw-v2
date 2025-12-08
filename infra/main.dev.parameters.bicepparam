using 'main.bicep'

param environment = 'dev'

param suffix = 'genaishared'

param rgLocation = 'westeurope'

param apimPublisherEmail = 'heenarefai@microsoft.com'

param apimPublisherName = 'AIGatewayTeam'

param apimSku = 'StandardV2'

param openAILocations = [
  {
    name: 'westeurope'
    abbreviation: 'we'
    deployments: [
      {
        deploymentName: 'gpt-4o-mini-2024-07-18'
        skuName: 'DataZoneStandard'
        skuCapacity: 10
        name: 'gpt-4o-mini'
        version: '2024-07-18'
        format: 'OpenAI'
        priority: 2
        raiPolicyName: 'Microsoft.DefaultV2'
      }
    ]
  }
  {
    name: 'swedencentral'
    abbreviation: 'sc'
    deployments: [
      {
        deploymentName: 'gpt-4o-mini-2024-07-18-standard'
        skuName: 'Standard'
        skuCapacity: 30
        name: 'gpt-4o-mini'
        version: '2024-07-18'
        format: 'OpenAI'
        priority: 1
        raiPolicyName: 'Microsoft.DefaultV2'
      }
      {
        deploymentName: 'gpt-4o-mini-2024-07-18'
        skuName: 'DataZoneStandard'
        skuCapacity: 10
        name: 'gpt-4o-mini'
        version: '2024-07-18'
        format: 'OpenAI'
        priority: 1
        raiPolicyName: 'Microsoft.DefaultV2'
      }

      {
        deploymentName: 'Phi-4'
        skuName: 'GlobalStandard'
        skuCapacity: 1
        name: 'Phi-4'
        version: '7'
        format: 'Microsoft'
        priority: 1
        raiPolicyName: 'Microsoft.DefaultV2'
      }
    ]
  }
  {
    name: 'francecentral'
    abbreviation: 'fc'
    deployments: [
      {
        deploymentName: 'gpt-4o-mini-2024-07-18'
        skuName: 'DataZoneStandard'
        skuCapacity: 10
        name: 'gpt-4o-mini'
        version: '2024-07-18'
        format: 'OpenAI'
        priority: 1
        raiPolicyName: 'Microsoft.DefaultV2'
      }
    ]
  }
]

param vnetName = 'vnet-acc-kpn'

param createNewVnet = true

param vnetAddressPrefixes = [
  '10.50.0.0/20'
]

param apimSubnetPrefix = '10.50.0.0/27'

param pepSubnetPrefix = '10.50.1.0/24'

param virtualNetworkType = 'External'

param enforcePrivateAccess = true

param allowedCognitivePrivateEndpointIps = []

param aiPrivateEndpointSubnetId = ''

param enableApimGatewayPrivateEndpoint = true

// Set to true to disable public network access to APIM (only after validating private endpoint works)
param disableApimPublicAccess = false

param apimPeSubnetPrefix = '10.50.2.0/28'

param appGwSubnetPrefix = '10.50.3.0/27'

param appGwCertificateName = 'appgw-cert'
