@description('The name of the existing API Management service')
param apimServiceName string

@description('The OpenAI-compatible Databricks serving base URL')
param databricksEndpoint string

@secure()
@description('Databricks PAT or OAuth access token')
param databricksApiToken string

@description('Public APIM path for the Databricks OpenAI-compatible API')
param apiPath string = 'databricks/v1'

@description('App role required to call the Databricks API')
param requiredRole string

@description('OpenAI v1 specification content')
param openApiSpec string

@description('APIM policy for the Databricks API')
param policyXml string

resource apimService 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimServiceName
}

resource appInsightsLogger 'Microsoft.ApiManagement/service/loggers@2024-06-01-preview' existing = {
  parent: apimService
  name: 'appinsights-logger'
}

resource databricksToken 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: apimService
  name: 'databricks-api-token'
  properties: {
    displayName: 'databricks-api-token'
    secret: true
    value: databricksApiToken
  }
}

resource databricksRequiredRole 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: apimService
  name: 'databricks-required-role'
  properties: {
    displayName: 'databricks-required-role'
    secret: false
    value: requiredRole
  }
}

resource databricksBackend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = {
  parent: apimService
  name: 'databricks-llm-backend'
  properties: {
    description: 'OpenAI-compatible Databricks model serving backend'
    url: databricksEndpoint
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
    circuitBreaker: {
      rules: [
        {
          name: 'breakonthrottle'
          failureCondition: {
            count: 1
            interval: 'PT10S'
            statusCodeRanges: [
              {
                min: 429
                max: 429
              }
            ]
            errorReasons: []
          }
          tripDuration: 'PT10S'
          acceptRetryAfter: true
        }
      ]
    }
  }
}

resource databricksApi 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: apimService
  name: 'databricks-openai-api'
  properties: {
    displayName: 'Databricks OpenAI-compatible API'
    description: 'Databricks model serving exposed as an APIM language model API'
    path: apiPath
    protocols: [
      'https'
    ]
    subscriptionRequired: false
    type: 'http'
    format: 'openapi+json'
    value: openApiSpec
    serviceUrl: databricksEndpoint
  }
}

resource databricksApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = {
  parent: databricksApi
  name: 'policy'
  properties: {
    value: policyXml
    format: 'rawxml'
  }
  dependsOn: [
    databricksBackend
    databricksRequiredRole
    databricksToken
  ]
}

resource databricksApiDiagnostics 'Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview' = {
  parent: databricksApi
  name: 'applicationinsights'
  properties: {
    loggerId: appInsightsLogger.id
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    logClientIp: true
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    largeLanguageModel: {
      logs: 'enabled'
    }
    metrics: true
  }
}

output apiId string = databricksApi.name
output gatewayPath string = apiPath
output backendId string = databricksBackend.name
