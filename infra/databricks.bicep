targetScope = 'resourceGroup'

@description('The name of the existing API Management service')
param apimServiceName string

@description('The OpenAI-compatible Databricks serving base URL, for example https://<workspace>/serving-endpoints')
param databricksEndpoint string

@secure()
@description('Databricks PAT or OAuth access token')
param databricksApiToken string

@description('Public APIM path for the Databricks API')
param apiPath string = 'databricks/v1'

@description('App role required to call the Databricks API')
param requiredRole string = 'databricks-access'

module databricksApi 'modules/databricks-llm-api.bicep' = {
  name: 'deploy-databricks-llm-api'
  params: {
    apimServiceName: apimServiceName
    databricksEndpoint: databricksEndpoint
    databricksApiToken: databricksApiToken
    apiPath: apiPath
    requiredRole: requiredRole
    openApiSpec: loadTextContent('../openapi/openai-v1.json')
    policyXml: loadTextContent('../apim-policies/databricks-policy.xml')
  }
}

output apiId string = databricksApi.outputs.apiId
output gatewayUrl string = 'https://${apimServiceName}.azure-api.net/${databricksApi.outputs.gatewayPath}'
output backendId string = databricksApi.outputs.backendId
