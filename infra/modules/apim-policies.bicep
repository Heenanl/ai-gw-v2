@description('The name of the APIM service')
param apimServiceName string

@description('Azure OpenAI API policy XML content')
param aoaiPolicyXml string

@description('OpenAI v1 API policy XML content')
param oaiv1PolicyXml string

@description('OpenAI v1 model discovery policy XML content')
param oaiv1ModelsPolicyXml string

@description('Deployment names exposed by OpenAI v1 model discovery')
param modelNames array

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

resource listModelsOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' existing = {
  parent: oaiv1Api
  name: 'listModels'
}

resource retrieveModelOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' existing = {
  parent: oaiv1Api
  name: 'retrieveModel'
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

var oaiv1ModelsPolicy = replace(oaiv1ModelsPolicyXml, '__MODEL_NAMES_BASE64__', base64(string(modelNames)))

resource listModelsPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-05-01-preview' = {
  parent: listModelsOperation
  name: 'policy'
  properties: {
    value: oaiv1ModelsPolicy
    format: 'rawxml'
  }
}

resource retrieveModelPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-05-01-preview' = {
  parent: retrieveModelOperation
  name: 'policy'
  properties: {
    value: oaiv1ModelsPolicy
    format: 'rawxml'
  }
}

// Outputs
output aoaiPolicyApplied bool = true
output oaiv1PolicyApplied bool = true
output oaiv1ModelsPolicyApplied bool = true
