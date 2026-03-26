using 'main.bicep'

// ============================================================================
// Public Foundry - Test Connection
// ============================================================================

param aiFoundryAccountName = 'foundry-public-01'
param aiFoundryProjectName = 'proj-default'
param connectionName = 'citadel-hub-connection'
param apimGatewayUrl = 'https://apim-dev-genaishared-gk4ctyapmcrrw.azure-api.net'
param apiPath = 'openai'

// PMI Auth
param authType = 'ProjectManagedIdentity'
param audience = 'api://fa574d59-83f3-46ad-9e6a-9dc8ab830ff7'
param isSharedToAll = true

// APIM Config
param deploymentInPath = 'true'
param inferenceAPIVersion = '2024-12-01-preview'

// Static Models
param staticModels = [
  {
    name: 'gpt-5-mini'
    properties: {
      model: {
        name: 'gpt-5-mini'
        version: '2025-08-07'
        format: 'OpenAI'
      }
    }
  }
  {
    name: 'gpt-4o-mini-2024-07-18'
    properties: {
      model: {
        name: 'gpt-4o-mini'
        version: '2024-07-18'
        format: 'OpenAI'
      }
    }
  }
]

// Disable dynamic discovery (override defaults to force static models)
param listModelsEndpoint = ''
param getModelEndpoint = ''
param deploymentProvider = ''
