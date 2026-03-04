@description('The name of the API Management service')
param apimName string

@description('The location for the APIM service')
param location string = resourceGroup().location

@description('Tags to apply to the resource')
param tags object = {}

@description('The SKU of the APIM service')
@allowed(['BasicV2', 'StandardV2'])
param sku string = 'StandardV2'

@description('Publisher email for APIM')
param publisherEmail string

@description('Publisher name for APIM')
param publisherName string

@description('User-assigned managed identity resource ID')
param managedIdentityId string

@description('Application Insights instrumentation key')
param appInsightsInstrumentationKey string

@description('Application Insights resource ID')
param appInsightsId string

// API Management Service
resource apimService 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: sku
    capacity: sku == 'Developer' ? 1 : 1
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

// Azure OpenAI API (native format) - import from OpenAPI spec
resource azureOpenAIApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apimService
  name: 'azure-openai-api'
  properties: {
    displayName: 'Azure OpenAI Service API'
    description: 'Azure OpenAI native API format'
    path: 'openai'
    protocols: ['https']
    subscriptionRequired: true  
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'            // changed from api-key
      query: 'subscription-key'                      // changed from api-key
    }
    type: 'http'
    format: 'openapi+json'
    value: loadTextContent('../../openapi/azure-openai-2024-02-01.json')
    serviceUrl: 'https://placeholder.openai.azure.com'
  }
}

// OpenAI v1 API (OpenAI-compatible format) - import from OpenAPI spec
resource openAIv1Api 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apimService
  name: 'openai-v1-api'
  properties: {
    displayName: 'OpenAI v1 API'
    description: 'OpenAI v1 compatible API format'
    path: 'v1'
    protocols: ['https']
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
    type: 'http'
    format: 'openapi+json'
    value: loadTextContent('../../openapi/openai-v1.json')
    serviceUrl: 'https://placeholder.openai.azure.com'
  }
}

// Realtime WebSocket API - defined inline since it's simple and doesn't have a formal 3.0.x spec yet
resource openAIRealtimeApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apimService
  name: 'openai-realtime-ws-api'
  properties: {
    displayName: 'Azure OpenAI Realtime API'
    description: 'Azure OpenAI Realtime WebSocket API (wss) for audio/speech models'
    path: 'openai/realtime'
    protocols: ['wss']
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
    type: 'websocket'
    serviceUrl: 'wss://placeholder.openai.azure.com/openai/realtime'
  }
}

// Realtime Usage Reporting API (HTTP - called by client after session ends)
resource openAIRealtimeUsageApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apimService
  name: 'openai-realtime-usage-api'
  properties: {
    displayName: 'Azure OpenAI Realtime Usage Reporting API'
    description: 'HTTP endpoint for clients to report token usage after a realtime session'
    path: 'openai/realtime-usage'
    protocols: ['https']
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
    type: 'http'
    serviceUrl: 'https://placeholder.openai.azure.com'
  }
}

// POST /report operation - HTTP APIs require at least one operation to be routable
resource realtimeUsageReportOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: openAIRealtimeUsageApi
  name: 'report-usage'
  properties: {
    displayName: 'Report Usage'
    method: 'POST'
    urlTemplate: '/'
    description: 'Report token usage from a completed realtime session'
  }
}
// Application Insights logger
resource apimLogger 'Microsoft.ApiManagement/service/loggers@2023-09-01-preview' = {
  parent: apimService
  name: 'appinsights-logger'
  properties: {
    loggerType: 'applicationInsights'
    description: 'Application Insights logger for OpenAI APIs'
    credentials: {
      instrumentationKey: appInsightsInstrumentationKey
    }
    isBuffered: true
    resourceId: appInsightsId
  }
}

// Diagnostics for Azure OpenAI API
resource azureOpenAIDiagnostics 'Microsoft.ApiManagement/service/apis/diagnostics@2023-09-01-preview' = {
  parent: azureOpenAIApi
  name: 'applicationinsights'
  properties: {
    loggerId: apimLogger.id
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    logClientIp: true
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    metrics: true
  }
}

// Diagnostics for OpenAI v1 API
resource openAIv1Diagnostics 'Microsoft.ApiManagement/service/apis/diagnostics@2023-09-01-preview' = {
  parent: openAIv1Api
  name: 'applicationinsights'
  properties: {
    loggerId: apimLogger.id
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    logClientIp: true
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    metrics: true
  }
}

// Diagnostics for Realtime WebSocket API
resource realtimeDiagnostics 'Microsoft.ApiManagement/service/apis/diagnostics@2023-09-01-preview' = {
  parent: openAIRealtimeApi
  name: 'applicationinsights'
  properties: {
    loggerId: apimLogger.id
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    logClientIp: true
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    metrics: true
  }
}

// Diagnostics for Realtime Usage Reporting API
resource realtimeUsageDiagnostics 'Microsoft.ApiManagement/service/apis/diagnostics@2023-09-01-preview' = {
  parent: openAIRealtimeUsageApi
  name: 'applicationinsights'
  properties: {
    loggerId: apimLogger.id
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    logClientIp: true
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    metrics: true
  }
}

// Outputs
@description('The resource ID of the APIM service')
output apimId string = apimService.id

@description('The name of the APIM service')
output apimName string = apimService.name

@description('The gateway URL of the APIM service')
output apimGatewayUrl string = apimService.properties.gatewayUrl

@description('The Azure OpenAI API ID')
output azureOpenAIApiId string = azureOpenAIApi.id

@description('The OpenAI v1 API ID')
output openAIv1ApiId string = openAIv1Api.id

output openAIRealtimeApiId string = openAIRealtimeApi.id
output openAIRealtimeUsageApiId string = openAIRealtimeUsageApi.id
