/*
===========================================
APIM Connection - Template (PMI Auth)
===========================================

Template parameter file for creating an APIM connection in a Foundry project
using ProjectManagedIdentity (PMI) authentication.

PREREQUISITES:
  1. The project's managed identity must be assigned app roles in the
     Entra ID app registration for each deployment it needs access to.

     To find the project MI:
       az rest --method GET \
         --url ".../accounts/<account>/projects/<project>?api-version=2025-04-01-preview" \
         --query "identity.principalId" -o tsv

     To assign app roles (using Az PowerShell):
       New-AzADServicePrincipalAppRoleAssignment \
         -ServicePrincipalId <project-mi-id> \
         -ResourceId <app-registration-sp-id> \
         -AppRoleId <role-id>

  2. APIM named values 'aad-tenant' and 'apim-audience' must be configured.

  3. The Foundry account must have public network access enabled, OR
     the Agent Service subnet must be able to reach the APIM endpoint.

USAGE:
  # Copy this file and fill in your values
  cp agent.template.bicepparam my-agent.bicepparam

  az account set --subscription <foundry-subscription-id>
  az deployment group create \
    --name foundry-apim-connection \
    --resource-group <foundry-resource-group> \
    --template-file main.bicep \
    --parameters my-agent.bicepparam
*/

using 'main.bicep'

// ============================================================================
// REQUIRED: AI Foundry Configuration
// Replace with your Foundry account and project names
// ============================================================================
param aiFoundryAccountName = '<YOUR-AI-FOUNDRY-ACCOUNT-NAME>'
param aiFoundryProjectName = '<YOUR-AI-FOUNDRY-PROJECT-NAME>'

// ============================================================================
// REQUIRED: Connection Configuration
// ============================================================================
param connectionName = 'citadel-hub-connection'

// ============================================================================
// REQUIRED: APIM Gateway Configuration
// Replace with your APIM gateway URL
// ============================================================================
param apimGatewayUrl = '<YOUR-APIM-GATEWAY-URL>'   // e.g., https://my-apim.azure-api.net
param apiPath = 'openai'

// ============================================================================
// Authentication: ProjectManagedIdentity (PMI)
// The project's managed identity acquires a JWT token for the specified
// audience. Replace with your Entra ID app registration Application ID URI.
// ============================================================================
param authType = 'ProjectManagedIdentity'
param audience = 'api://<YOUR-APIM-APP-REGISTRATION-CLIENT-ID>'
param isSharedToAll = true

// ============================================================================
// APIM Configuration
// inferenceAPIVersion must match an api-version accepted by your APIM API
// ============================================================================
param deploymentInPath = 'true'
param inferenceAPIVersion = '2024-12-01-preview'

// ============================================================================
// Static Models
// List the models available through your APIM gateway.
// Each model name must match a deployment name in your APIM backend pool.
// The project MI must have an app role assigned for each model name.
// ============================================================================
param staticModels = [
  {
    name: '<DEPLOYMENT-NAME>'           // e.g., 'gpt-5-mini'
    properties: {
      model: {
        name: '<MODEL-NAME>'            // e.g., 'gpt-5-mini'
        version: '<MODEL-VERSION>'      // e.g., '2025-08-07'
        format: 'OpenAI'
      }
    }
  }
  // Add more models as needed:
  // {
  //   name: 'gpt-4o-mini-2024-07-18'
  //   properties: {
  //     model: {
  //       name: 'gpt-4o-mini'
  //       version: '2024-07-18'
  //       format: 'OpenAI'
  //     }
  //   }
  // }
]

// Disable dynamic discovery (required when using static models)
param listModelsEndpoint = ''
param getModelEndpoint = ''
param deploymentProvider = ''
