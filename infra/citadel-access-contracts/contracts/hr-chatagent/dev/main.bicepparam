using '../../../main.bicep'

// ============================================================================
// HR Chat Agent - Key Vault + Foundry (if enabled) - Generated from Notebook
// ============================================================================

param apim = {
  subscriptionId: '86c7aa63-b073-47bb-b0af-2afa58ea8fac'
  resourceGroupName: 'rg-genai-dev-gw-v2'
  name: 'apim-dev-genaishared-gk4ctyapmcrrw'
}

param keyVault = {
  subscriptionId: 'd2e7f84f-2790-4baa-9520-59ae8169ed0d'
  resourceGroupName: 'rg-foundry-agent-spoke-01'
  name: 'kv-foundry-spoke-01'
}

param useTargetAzureKeyVault = false

param useCase = {
  businessUnit: 'HR'
  useCaseName: 'ChatAgent'
  environment: 'DEV'
}

param apiNameMapping = {
  LLM: ['openai-v1-api', 'azure-openai-api']
}

param services = [
  {
    code: 'LLM'
    endpointSecretName: 'HR-LLM-ENDPOINT'
    apiKeySecretName: 'HR-LLM-KEY'
    policyXml: loadTextContent('ai-product-policy.xml')
  }
]

param productTerms = 'Access Contract created from testing notebook - HR Chat Agent - Key Vault + Foundry (if enabled)'

// Azure AI Foundry Integration
param useTargetFoundry = false

param foundry = {
  subscriptionId: '86c7aa63-b073-47bb-b0af-2afa58ea8fac'
  resourceGroupName: 'rg-genai-dev-gw-v2'
  accountName: 'apim-dev-genaishared-gk4ctyapmcrrw'
  projectName: 'crm-support-agent'
}

param foundryConfig = {
  connectionNamePrefix: ''
  deploymentInPath: 'false'
  isSharedToAll: false
  inferenceAPIVersion: ''
  deploymentAPIVersion: ''
  staticModels: []
  listModelsEndpoint: ''
  getModelEndpoint: ''
  deploymentProvider: ''
  customHeaders: {}
  authConfig: {}
}

