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
      {
        deploymentName: 'gpt-5-mini'
        skuName: 'DataZoneStandard'
        skuCapacity: 10
        name: 'gpt-5-mini'
        version: '2025-08-07'
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
        deploymentName: 'gpt-5-mini'
        skuName: 'GlobalStandard'
        skuCapacity: 30
        name: 'gpt-5-mini'
        version: '2025-08-07'
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
      {
        deploymentName: 'text-embedding-3-small'
        skuName: 'DataZoneStandard'
        skuCapacity: 10
        name: 'text-embedding-3-small'
        version: '1'
        format: 'OpenAI'
        priority: 1
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
      {
        deploymentName: 'text-embedding-3-small'
        skuName: 'DataZoneStandard'
        skuCapacity: 10
        name: 'text-embedding-3-small'
        version: '1'
        format: 'OpenAI'
        priority: 2
      }
    ]
  }
]
