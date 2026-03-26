/*
===========================================
APIM Connection - Private Foundry Agent (PMI Auth)
===========================================

Creates an APIM connection in the private Foundry project using
ProjectManagedIdentity (PMI) authentication. The Foundry Agent Service
uses the project's managed identity to acquire a JWT token for APIM.

PREREQUISITES:
  1. The project's managed identity AND the agent identity must be
     registered in the Entra ID app registration with app roles for
     each deployment they need access to (e.g., gpt-5-mini).

     To find the identities:
       Project MI:  az rest --method GET --url ".../accounts/<account>/projects/<project>?api-version=2025-04-01-preview" --query identity.principalId
       Agent ID:    az rest --method GET --url ".../accounts/<account>/projects/<project>?api-version=2025-04-01-preview" --query properties.agentIdentity.agentIdentityId

     To assign app roles (using Az PowerShell):
       New-AzADServicePrincipalAppRoleAssignment -ServicePrincipalId <identity-id> -ResourceId <app-sp-id> -AppRoleId <role-id>

  2. APIM named values 'aad-tenant' and 'apim-audience' must be configured.

  3. The Foundry account must have public network access enabled, OR
     the test must run from inside the Foundry's VNet.

USAGE:
  az account set --subscription <foundry-subscription-id>
  az deployment group create \
    --name foundry-apim-connection \
    --resource-group rg-foundry-private-v2 \
    --template-file main.bicep \
    --parameters private-agent.bicepparam
*/

using 'main.bicep'

// ============================================================================
// REQUIRED: AI Foundry Configuration
// ============================================================================
param aiFoundryAccountName = 'aiservices6u2x'
param aiFoundryProjectName = 'project2'

// ============================================================================
// REQUIRED: Connection Configuration
// ============================================================================
param connectionName = 'citadel-hub-connection'

// ============================================================================
// REQUIRED: APIM Gateway Configuration
// ============================================================================
param apimGatewayUrl = 'https://apim-dev-genaishared-gk4ctyapmcrrw.azure-api.net'
param apiPath = 'openai'

// ============================================================================
// Authentication: ProjectManagedIdentity (PMI)
// The project's managed identity acquires a JWT token for the specified
// audience. No subscription key needed.
// ============================================================================
param authType = 'ProjectManagedIdentity'
param audience = 'api://fa574d59-83f3-46ad-9e6a-9dc8ab830ff7'
param isSharedToAll = true

// ============================================================================
// APIM Configuration
// ============================================================================
param deploymentInPath = 'true'
param inferenceAPIVersion = '2024-12-01-preview'

// ============================================================================
// Static Models (avoids needing a /deployments discovery endpoint on APIM)
// List only the models the agent needs access to.
// ============================================================================
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
