@description('The name of the APIM service')
param apimServiceName string

@description('Azure OpenAI API policy XML content')
param aoaiPolicyXml string

@description('OpenAI v1 API policy XML content')
param oaiv1PolicyXml string

@description('Realtime WebSocket API policy XML content')
param realtimePolicyXml string

@description('Realtime Usage Reporting API policy XML content')
param realtimeUsagePolicyXml string


// Reference existing APIM service
resource apimService 'Microsoft.ApiManagement/service@2023-05-01-preview' existing = {
  name: apimServiceName
}

// Reference Azure OpenAI API
resource aoaiApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' existing = {
  parent: apimService
  name: 'azure-openai-api'
}

// Reference OpenAI v1 API
resource oaiv1Api 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' existing = {
  parent: apimService
  name: 'openai-v1-api'
}

//Reference Realtime WebSocket API
resource realtimeApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' existing = {
  parent: apimService
  name: 'openai-realtime-ws-api'
}

// Reference Realtime Usage Reporting API
resource realtimeUsageApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' existing = {
  parent: apimService
  name: 'openai-realtime-usage-api'
}

// WebSocket APIs do not support API-scope policies - policy must be on the onHandshake operation
// onHandshake is the HTTP upgrade handshake - immutable, auto-created system operation on every WebSocket API
resource realtimeOnHandshakeOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' existing = {
  parent: realtimeApi
  name: 'onHandshake'
}

resource realtimeOnConnectPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-05-01-preview' = {
  parent: realtimeOnHandshakeOperation
  name: 'policy'
  properties: {
    value: realtimePolicyXml
    format: 'rawxml'
  }
}

// HTTP API - policy applied at API scope as normal
resource realtimeUsageApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: realtimeUsageApi
  name: 'policy'
  properties: {
    value: realtimeUsagePolicyXml
    format: 'rawxml'
  }
}

// Apply policy to all operations in Azure OpenAI API
resource aoaiApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: aoaiApi
  name: 'policy'
  properties: {
    value: aoaiPolicyXml
    format: 'rawxml'
  }
}

// Apply policy to all operations in OpenAI v1 API
resource oaiv1ApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: oaiv1Api
  name: 'policy'
  properties: {
    value: oaiv1PolicyXml
    format: 'rawxml'
  }
}

// Outputs
output aoaiPolicyApplied bool = true
output oaiv1PolicyApplied bool = true
