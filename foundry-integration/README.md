# 🔌 Azure AI Foundry - APIM Connection Integration

This module enables Azure AI Foundry projects to access AI models through your Azure API Management (APIM) gateway, supporting the **Bring Your Own AI Gateway** pattern for enterprise AI governance.

## 📋 Overview

The APIM connection integration allows organizations to:

- **Maintain control** over model endpoints behind your existing governance hub
- **Build agents** that leverage models without exposing them publicly  
- **Apply governance** requirements to AI model access through APIM policies (JWT validation, role-based model access, token metrics)
- **Use Entra ID authentication** via ProjectManagedIdentity — no subscription keys needed

### Architecture

```mermaid
flowchart LR
    subgraph Foundry["Azure AI Foundry"]
        Project[AI Project]
        Agent[Foundry Agent]
    end
    
    subgraph Connection["APIM Connection"]
        Conn[Connection Config]
        PMI[Project Managed Identity]
    end
    
    subgraph Gateway["AI Gateway"]
        APIM[Azure API Management]
        Policy["JWT Validation<br/>Role-Based Access<br/>Token Metrics"]
    end
    
    subgraph Backend["AI Services"]
        AOAI[Azure OpenAI<br/>Multi-Region]
    end
    
    Agent --> Conn
    Conn -->|"Bearer JWT"| APIM
    APIM --> Policy
    Policy --> AOAI
```

### Request Flow

```mermaid
sequenceDiagram
    participant Agent as Foundry Agent
    participant PMI as Project MI
    participant APIM as API Management
    participant Backend as Azure OpenAI

    Agent->>PMI: Acquire JWT token<br/>(audience: api://app-id)
    PMI-->>Agent: Bearer token (with roles claim)
    Agent->>APIM: POST /openai/deployments/{model}/chat/completions<br/>Authorization: Bearer {jwt}
    APIM->>APIM: validate-azure-ad-token<br/>Check roles claim contains deployment name
    APIM->>APIM: Set backend pool, managed identity auth
    APIM->>Backend: Forward request
    Backend-->>APIM: Response
    APIM->>APIM: Emit token metrics
    APIM-->>Agent: Response
```

---

## 📁 Folder Structure

```
foundry-integration/
├── main.bicep                          # Main deployment template (supports ApiKey, AAD, PMI)
├── private-agent.bicepparam            # Parameters for private Foundry (aiservices6u2x/project2)
├── public-foundry.bicepparam           # Parameters for public Foundry (foundry-public-01/proj-default)
├── README.md                           # This documentation
└── ai-gateway/                         # Full Foundry + APIM deployment template (azd)
```

---

## ✅ Prerequisites

| Requirement | Description |
|-------------|-------------|
| **Azure Subscription** | Access to subscription containing AI Foundry |
| **AI Foundry Project** | Existing Foundry account and project with Agent Service configured |
| **APIM Gateway** | Deployed AI Gateway with `azure-openai-api` (path: `openai`) |
| **Entra ID App Registration** | App registration with app roles per deployment name |
| **Azure CLI** | Latest version with Bicep support |
| **Permissions** | Contributor on Foundry resource group, Application Administrator for role assignments |

---

## 🚀 Quick Start

### Step 1: Configure Parameters

Copy an existing parameter file and edit:

```bash
cp public-foundry.bicepparam my-project.bicepparam
```

Edit `my-project.bicepparam`:

```bicep
using 'main.bicep'

param aiFoundryAccountName = 'my-foundry-account'
param aiFoundryProjectName = 'my-project'
param connectionName = 'citadel-hub-connection'
param apimGatewayUrl = 'https://my-apim.azure-api.net'
param apiPath = 'openai'

// PMI Auth — no subscription key needed
param authType = 'ProjectManagedIdentity'
param audience = 'api://your-app-registration-client-id'
param isSharedToAll = true

// APIM Config
param deploymentInPath = 'true'
param inferenceAPIVersion = '2024-12-01-preview'  // Must match APIM api-version

// Static models (required if APIM lacks /deployments endpoint)
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
]

// Disable dynamic discovery (override non-empty defaults)
param listModelsEndpoint = ''
param getModelEndpoint = ''
param deploymentProvider = ''
```

### Step 2: Assign App Roles to Agent Identity

The Agent Service uses a separate **agent identity** (auto-created when agents are configured) for outbound calls to APIM. This identity acquires the JWT token.

```powershell
# 1. Get the agent identity ID
az rest --method GET `
  --url ".../accounts/<account>/projects/<project>?api-version=2025-04-01-preview" `
  --query "properties.agentIdentity.agentIdentityId"

# 2. Assign app roles to the agent identity (for each model)
#    ResourceId = SP object ID of your app registration
#    AppRoleId  = ID of the app role matching the deployment name
New-AzADServicePrincipalAppRoleAssignment `
  -ServicePrincipalId <agent-identity-id> `
  -ResourceId <app-registration-sp-id> `
  -AppRoleId <role-id-for-deployment>
```

> **⚠️ JWT role enforcement under investigation:** Testing showed requests succeed even without app roles assigned. The APIM `validate-azure-ad-token` policy accepts the PMI token but the `roles` claim check may not enforce correctly for managed identity tokens. Assign roles as best practice; further investigation needed on the policy's C# expression handling of SPN token claims.
>
> **Token caching:** Entra ID tokens are cached ~60-75 min. Role changes don't take effect until the token expires or the connection is deleted and recreated.

### Step 3: Deploy

```bash
az account set --subscription <foundry-subscription-id>

az deployment group create \
  --name foundry-apim-connection \
  --resource-group <foundry-resource-group> \
  --template-file main.bicep \
  --parameters my-project.bicepparam
```

### Step 4: Verify

Check the connection in Azure AI Foundry portal:
1. Navigate to your Foundry project
2. Go to **Connected resources**
3. Verify the connection appears with an Active status

### Step 5: Test

```bash
pip install azure-ai-projects>=2.0.0 azure-identity

export FOUNDRY_ACCOUNT=my-foundry-account
export FOUNDRY_PROJECT=my-project
python tests/test_foundry_agent.py
```

---

## 🔧 Configuration Details

### Authentication Types

| Type | `authType` Value | How It Works |
|------|-----------------|--------------|
| **ProjectManagedIdentity** (recommended) | `'ProjectManagedIdentity'` | Agent Service uses PMI to acquire JWT for the specified `audience`. Requires app role assignments. |
| **ApiKey** | `'ApiKey'` | Subscription key passed in `api-key` header. Requires `apimSubscriptionKey`. |
| **AAD** | `'AAD'` | ⚠️ Not recommended — causes "Connection not found" at runtime. Use `ProjectManagedIdentity` instead. |

### Model Discovery

| Method | When to Use | Key Settings |
|--------|-------------|-------------|
| **Static Models** (recommended) | APIM doesn't expose `/deployments` list endpoint | `staticModels = [...]`, set discovery params to `''` |
| **Dynamic Discovery** | APIM has `/deployments` endpoint configured | `listModelsEndpoint`, `getModelEndpoint`, `deploymentProvider` |

> ⚠️ **Important**: The template has non-empty defaults for `listModelsEndpoint` (`/deployments`), `getModelEndpoint` (`/deployments/{deployment-id}`), and `deploymentProvider` (`AzureOpenAI`). When using static models, you **must** explicitly set these to empty strings to prevent dynamic discovery from being enabled.

### Critical Parameters

| Parameter | Required Value | Why |
|-----------|---------------|-----|
| `inferenceAPIVersion` | `'2024-12-01-preview'` | APIM operation template includes `api-version` as a URL parameter. Without it, requests return 404. |
| `deploymentInPath` | `'true'` | Matches the `azure-openai-api` URL pattern: `/deployments/{model}/chat/completions` |
| `apiPath` | `'openai'` | Matches the APIM API path for `azure-openai-api` |
| `audience` | `'api://<app-client-id>'` | Must match the APIM `validate-azure-ad-token` audience |

---

## 📋 Parameter Reference

### Required Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `aiFoundryAccountName` | string | Name of the AI Foundry account |
| `aiFoundryProjectName` | string | Name of the project within Foundry |
| `connectionName` | string | Unique name for the connection |
| `apimGatewayUrl` | string | APIM gateway URL (e.g., `https://my-apim.azure-api.net`) |
| `apiPath` | string | API path in APIM (e.g., `openai`) |

### Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `apimSubscriptionKey` | string | `''` | APIM subscription key (only for `ApiKey` auth) |
| `authType` | string | `'ApiKey'` | Authentication type: `ApiKey`, `AAD`, or `ProjectManagedIdentity` |
| `audience` | string | `''` | Token audience for PMI auth |
| `isSharedToAll` | bool | `false` | Share connection with all project users |
| `deploymentInPath` | string | `'false'` | Deployment name in URL path |
| `inferenceAPIVersion` | string | `''` | API version for inference calls |
| `staticModels` | array | `[]` | Static model list |
| `listModelsEndpoint` | string | `'/deployments'` | Discovery list endpoint (set to `''` for static models) |
| `getModelEndpoint` | string | `'/deployments/{deployment-id}'` | Discovery get endpoint (set to `''` for static models) |
| `deploymentProvider` | string | `'AzureOpenAI'` | Discovery provider format (set to `''` for static models) |
| `customHeaders` | object | `{}` | Custom request headers |
| `authConfig` | object | `{}` | Custom auth configuration |

---

## 🧪 Using the Connection in Agents

After creating the connection, use the `azure-ai-projects` SDK (v2.0.0+):

```python
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import PromptAgentDefinition
from azure.identity import DefaultAzureCredential

# Initialize client
project_client = AIProjectClient(
    endpoint="https://my-foundry.services.ai.azure.com/api/projects/my-project",
    credential=DefaultAzureCredential()
)

# Create prompt agent with connection_name/model_name format
agent = project_client.agents.create_version(
    agent_name="my-agent",
    definition=PromptAgentDefinition(
        model="citadel-hub-connection/gpt-5-mini",
        instructions="You are a helpful assistant."
    )
)

# Chat using conversations + responses API
with project_client.get_openai_client() as openai_client:
    conversation = openai_client.conversations.create(
        items=[{"type": "message", "role": "user", "content": "Hello!"}]
    )
    response = openai_client.responses.create(
        conversation=conversation.id,
        extra_body={"agent_reference": {"name": agent.name, "type": "agent_reference"}},
        input=""
    )
    print(response.output_text)

# Cleanup
project_client.agents.delete_version(agent_name=agent.name, agent_version=agent.version)
```

See `tests/test_foundry_agent.py` for a complete working example.

---

## 📚 References

- [Connect an AI gateway to Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/ai-gateway)
- [APIM Connection Objects](https://github.com/azure-ai-foundry/foundry-samples/blob/main/infrastructure/infrastructure-setup-bicep/01-connections/apim/APIM-Connection-Objects.md)
- [Foundry Samples Repository](https://github.com/azure-ai-foundry/foundry-samples)
- [Azure AI Projects Agent Samples](https://github.com/Azure/azure-sdk-for-python/tree/main/sdk/ai/azure-ai-projects/samples/agents)
- [Private Network APIM Setup](https://github.com/azure-ai-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/16-private-network-standard-agent-apim-setup-preview)

---

## ⚠️ Known Limitations

| Limitation | Details |
|------------|---------|
| **Preview Status** | Feature is in preview with potential breaking changes |
| **UI Support** | Requires Azure CLI/Bicep for connection management |
| **Agent Support** | Only Prompt Agents in the Agent SDK |
| **APIM Tiers** | Standard v2 and Premium tiers supported |
| **Auth Types** | `ProjectManagedIdentity` and `ApiKey` work; `AAD` causes runtime issues |
| **isSharedToAll** | ARM API ignores this property (always returns `false`), but PMI connections work regardless |
| **Private Networking** | Private Foundry requires public access on the account or APIM private endpoint in the agent VNet |
| **agent_reference** | The `extra_body` property name is `agent_reference` (not `agent` — deprecated) |

