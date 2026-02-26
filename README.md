# Azure AI Gateway v2

A multi-region Azure AI Gateway implementation using Azure API Management (APIM) with priority-based backend pools, circuit breaker patterns, and comprehensive monitoring for Azure OpenAI deployments.

## 🏗️ Architecture Overview

This solution creates a resilient, multi-region Azure AI Gateway that:

- **Multi-Region Resilience**: Deploys Azure AI Foundry accounts across 3 regions with automatic failover
- **Priority-Based Routing**: Routes requests to regional backends based on configurable priority (1→2→3)
- **Circuit Breaker Pattern**: Opens circuit for 10 seconds on a single 429 error, preventing cascading failures
- **Dual API Support**: Supports both Azure OpenAI native format (`/openai/deployments/*`) and OpenAI v1 compatible format (`/v1/*`)
- **Managed Identity Authentication**: Uses Azure managed identity for secure, keyless authentication to AI Foundry
- **Entra ID JWT Auth** *(branch: `jwtauth`)*: Per-deployment access control via Entra ID app roles
- **Citadel Access Contracts** *(branch: `usecaseonboard`)*: Declarative IaC onboarding of use cases following the [Foundry Citadel Platform](https://github.com/azure-samples/ai-hub-gateway-solution-accelerator/tree/citadel-v1) AI Access Contract principle
- **Comprehensive Monitoring**: Application Insights integration with token usage tracking

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                          API Consumer                            │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Azure API Management (APIM)                    │
│                       (West Europe)                              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  APIs:                                                    │  │
│  │  • /openai/deployments/* (Azure OpenAI format)           │  │
│  │  • /v1/* (OpenAI compatible format)                      │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Backend Pools (per model):                              │  │
│  │  • pool-gpt-4o-mini-2024-dot-07-dot-18                   │  │
│  │    - Priority 1: West Europe                             │  │
│  │    - Priority 2: North Europe                            │  │
│  │    - Priority 3: Sweden Central                          │  │
│  │  Circuit Breaker: 1x 429 → 10s timeout                   │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────┬───────────────────────┬───────────────────────┬─────────┘
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐      ┌───────────────┐      ┌───────────────┐
│ AI Foundry    │      │ AI Foundry    │      │ AI Foundry    │
│ West Europe   │      │ North Europe  │      │ Sweden Central│
│ (Priority 1)  │      │ (Priority 2)  │      │ (Priority 3)  │
└───────────────┘      └───────────────┘      └───────────────┘
        │                       │                       │
        └───────────────────────┴───────────────────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │ Azure Monitor         │
                    │ • Log Analytics       │
                    │ • Application Insights│
                    └───────────────────────┘
```

## 🚀 Features

### Multi-Region Deployment
- AI Foundry accounts deployed across 3 configurable regions
- Each region hosts model deployments with the same model versions
- Regional endpoints automatically configured as APIM backends

### Backend Pool Configuration
- One backend pool per unique model deployment name
- Backends organized by strict priority order (1, 2, 3)
- Circuit breaker with single 429 threshold and 10-second trip duration

### Authentication & Security
- Single user-assigned managed identity for APIM
- Managed identity granted `Cognitive Services OpenAI User` and `Azure AI Developer` roles
- All authentication handled in APIM policies (no API keys stored)

### Monitoring & Observability
- Application Insights for telemetry and diagnostics
- Log Analytics workspace for log aggregation
- Azure OpenAI token metrics emitted for usage tracking
- Request/response logging with deployment tracking

## 📋 Prerequisites

- Azure subscription with sufficient quota for:
  - API Management StandardV2 SKU
  - Azure AI Foundry (Cognitive Services) in 3 regions
  - Log Analytics workspace
- Azure CLI installed ([Install guide](https://docs.microsoft.com/cli/azure/install-azure-cli))
- PowerShell 7+ (for deployment script)
- Appropriate Azure permissions:
  - Contributor role on target subscription/resource group
  - User Access Administrator (for RBAC assignments)

## 🛠️ Deployment

### 1. Configure Parameters

Edit `infra/main.acc.parameters.bicepparam`:

```bicep
using 'main.bicep'

param environment = 'acc'
param suffix = 'genaishared'
param rgLocation = 'westeurope'
param apimPublisherEmail = 'your-email@example.com'
param apimPublisherName = 'Your Organization'
param apimSku = 'StandardV2'

param openAILocations = [
  {
    name: 'westeurope'
    abbreviation: 'weu'
    deployments: [
      {
        deploymentName: 'gpt-4o-mini-2024-07-18-standard'
        name: 'gpt-4o-mini'
        version: '2024-07-18'
        format: 'OpenAI'
        skuName: 'Standard'
        skuCapacity: 10
        priority: 1
      }
    ]
  }
  {
    name: 'northeurope'
    abbreviation: 'neu'
    deployments: [
      {
        deploymentName: 'gpt-4o-mini-2024-07-18-standard'
        name: 'gpt-4o-mini'
        version: '2024-07-18'
        format: 'OpenAI'
        skuName: 'Standard'
        skuCapacity: 10
        priority: 2
      }
    ]
  }
  {
    name: 'swedencentral'
    abbreviation: 'swc'
    deployments: [
      {
        deploymentName: 'gpt-4o-mini-2024-07-18-standard'
        name: 'gpt-4o-mini'
        version: '2024-07-18'
        format: 'OpenAI'
        skuName: 'Standard'
        skuCapacity: 10
        priority: 3
      }
    ]
  }
]
```

### 2. Update Resource Group Configuration

Edit `infra/resourcegroup.config.json`:

```json
{
  "resourceGroupNames": ["rg-ai-gateway-acc"],
  "tags": {
    "environment": "acceptance",
    "project": "ai-gateway",
    "costCenter": "IT"
  }
}
```

### 3. Run Deployment

```powershell
# Login to Azure
az login

# Deploy infrastructure (dry run)
.\deploy.ps1 -WhatIf

# Deploy infrastructure
.\deploy.ps1

# Deploy to specific subscription
.\deploy.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012"
```

> **Next step — onboard a use case**: After the gateway is deployed, follow the [Use-Case Onboarding Guide](docs/usecaseonboard.md) to configure JWT authentication and deploy an AI Access Contract (APIM product + subscription key) for each use case.

### 4. Verify Deployment

The deployment script outputs key information:

```
Deployment Outputs:
==================
APIM Gateway URL: https://apim-acc-genaishared-xxxxx.azure-api.net
APIM Name: apim-acc-genaishared-xxxxx
Managed Identity Client ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
Log Analytics Workspace ID: /subscriptions/.../workspaces/law-acc-genaishared
```

## 🧪 Testing

### Setup Test Environment

```powershell
# Create and activate virtual environment
python -m venv .venv
.\.venv\Scripts\Activate.ps1

# Install test dependencies
pip install -r tests/requirements.txt

# Authenticate with Azure
az login
```

### Run Tests

```powershell
# Test Azure OpenAI native format
cd tests
python test_azure_openai.py

# Test OpenAI v1 compatible format
python test_openai_v1.py

# Test models endpoint
python test_models_v1.py
```

See [tests/README.md](tests/README.md) for detailed testing documentation.

## 📁 Project Structure

```
ai-gw-v2/
├── deploy.ps1                          # Deployment automation script
├── README.md                           # This file
│
├── docs/
│   └── usecaseonboard.md               # JWT auth + use-case onboarding guide
│
├── infra/                              # Infrastructure as Code
│   ├── main.bicep                      # Main orchestration template
│   ├── main.dev.parameters.bicepparam  # Environment parameters
│   ├── main.json                       # Compiled ARM template
│   ├── resourcegroup.config.json       # Resource group configuration
│   ├── modules/                        # Bicep modules
│   │   ├── ai-foundry.bicep
│   │   ├── ai-foundry-rbac.bicep
│   │   ├── apim.bicep
│   │   ├── apim-backend-pools.bicep
│   │   ├── apim-config.bicep
│   │   ├── apim-policies.bicep
│   │   ├── app-insights.bicep
│   │   ├── log-analytics.bicep
│   │   └── model-deployments.bicep
│   ├── citadel-access-contracts/       # Use-case onboarding module (branch: usecaseonboard)
│   │   ├── main.bicep
│   │   ├── main.bicepparam
│   │   ├── README.md
│   │   ├── modules/
│   │   ├── policies/
│   │   └── contracts/                  # Per-use-case contract files
│   │       └── hr-chatagent/dev/       # Example contract
│   └── specs/
│       └── JWTAuthentication.md        # JWT auth design notes
├── apim-policies/
│   ├── aoai-policy.xml             # Azure OpenAI format policy
│   └── oaiv1-policy.xml            # OpenAI v1 format policy
├── openapi/
├── queries/
└── tests/
```

## 🔧 Configuration

### Backend Pool Settings

Backend pools are configured in `modules/apim-backend-pools.bicep`:

- **Circuit Breaker**: Single 429 response opens circuit
- **Trip Duration**: 10 seconds
- **Priority Routing**: Strict priority-based (1→2→3)
- **Health Checks**: Automatic backend health monitoring

### APIM Policy Features

Both `aoai-policy.xml` and `oaiv1-policy.xml` implement:

1. **Managed Identity Authentication**: Automatic token acquisition for Cognitive Services
2. **Dynamic Backend Selection**: Routes to correct backend pool based on deployment/model name
3. **Streaming Support**: Injects `stream_options.include_usage: true` for token tracking
4. **Token Metrics**: Emits usage metrics to Application Insights
5. **Retry Logic**: 2 retries with 1-second intervals on 429 errors

### Named Values

APIM named values (configured in `modules/apim-config.bicep`):

- `managed-identity-client-id`: Client ID of the APIM managed identity

## 📊 Monitoring

### Application Insights

Token usage metrics are automatically captured:
- Prompt tokens
- Completion tokens
- Total tokens
- Model deployment name
- Request ID
- Streaming flag

### Query Usage Metrics

Use the provided KQL query (`queries/token-metrics.kql`) in Log Analytics:

```kql
customMetrics
| where name startswith "AzureOpenAI"
| extend Deployment = tostring(customDimensions["Deployment"])
| extend Streaming = tostring(customDimensions["Streaming"])
| summarize 
    TotalRequests = count(),
    AvgPromptTokens = avg(valueMax),
    AvgCompletionTokens = avg(valueMax)
    by Deployment, Streaming
```

## 🔒 Security Considerations

1. **No API Keys**: All authentication uses Azure managed identity
2. **RBAC**: Minimal permissions granted (Cognitive Services OpenAI User, Azure AI Developer)
3. **Project-Level Scoping**: RBAC assignments scoped to individual AI Foundry projects
4. **Network Security**: Public access enabled (configure VNet integration if needed)
5. **Policy-Based Auth**: Authentication logic centralized in APIM policies
6. **Entra ID JWT Validation** *(branch: `jwtauth`)*: Every request validated against tenant, audience, and per-deployment app roles
7. **Subscription Key Isolation** *(branch: `usecaseonboard`)*: Each use case gets a dedicated APIM product and subscription key scoped to its governance policy

## 🚦 Rate Limiting & Circuit Breaking

### Circuit Breaker Behavior

1. **Normal Operation**: Requests route to Priority 1 backend
2. **Single 429 Error**: Circuit opens, backend excluded for 10 seconds
3. **Automatic Failover**: Traffic shifts to Priority 2 backend
4. **Auto-Recovery**: After 10 seconds, circuit closes and Priority 1 is retried

### Retry Logic

- **Retry Count**: 2 retries
- **Retry Interval**: 1 second
- **First Fast Retry**: Enabled
- **Retry Condition**: HTTP 429 (Too Many Requests)

## 🐛 Troubleshooting

### Check Backend Health

```powershell
# List all backends in APIM
az apim backend list --resource-group rg-ai-gateway-acc --service-name apim-acc-genaishared-xxxxx

# Show backend pool configuration
az apim backend show --resource-group rg-ai-gateway-acc --service-name apim-acc-genaishared-xxxxx --backend-id pool-gpt-4o-mini-2024-dot-07-dot-18
```

### View Logs

```powershell
# Query Application Insights logs
az monitor app-insights query --app <app-insights-id> --analytics-query "requests | where timestamp > ago(1h)"
```

### Common Issues

**Issue**: 401 Unauthorized errors
- **Solution**: Verify managed identity has correct RBAC roles on AI Foundry projects

**Issue**: 404 Backend not found
- **Solution**: Ensure deployment name matches backend pool name (dots replaced with `-dot-`)

**Issue**: 429 errors not triggering circuit breaker
- **Solution**: Check backend pool configuration has correct trip threshold (should be 1)

## 🌿 Branches: `jwtauth` & `usecaseonboard` — Auth & Use-Case Onboarding

These branches extend the base gateway with enterprise-grade access control following the **AI Access Contract** principle from the [Foundry Citadel Platform](https://github.com/azure-samples/ai-hub-gateway-solution-accelerator/tree/citadel-v1):

- **`jwtauth`** — Entra ID JWT validation + per-deployment app-role enforcement
- **`usecaseonboard`** — Subscription key enforcement + declarative use-case onboarding via Citadel Access Contracts

📄 Full setup guide (JWT auth + contract deployment + testing): [docs/usecaseonboard.md](docs/usecaseonboard.md)

📄 Citadel Access Contracts module reference: [infra/citadel-access-contracts/README.md](infra/citadel-access-contracts/README.md)

---

## 📚 Additional Resources

- [Azure API Management Documentation](https://docs.microsoft.com/azure/api-management/)
- [Azure OpenAI Service Documentation](https://docs.microsoft.com/azure/cognitive-services/openai/)
- [Azure AI Foundry Documentation](https://docs.microsoft.com/azure/ai-services/ai-foundry/)
- [Backend Circuit Breaker Pattern](https://docs.microsoft.com/azure/api-management/backends)
- [Foundry Citadel Platform — AI Access Contracts](https://github.com/azure-samples/ai-hub-gateway-solution-accelerator/tree/citadel-v1)
- [Use-Case Onboarding Guide](docs/usecaseonboard.md)
- [Citadel Access Contracts README](infra/citadel-access-contracts/README.md)

## 📝 License

This project is licensed under the MIT License.

## 🤝 Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## 📧 Support

For issues and questions:
1. Check the [Troubleshooting](#-troubleshooting) section
2. Review Application Insights logs
3. Open an issue in this repository
