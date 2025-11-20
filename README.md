# Azure AI Gateway v2

A multi-region Azure AI Gateway implementation using Azure API Management (APIM) with priority-based backend pools, circuit breaker patterns, and comprehensive monitoring for Azure OpenAI deployments.

## 🏗️ Architecture Overview

This solution creates a resilient, multi-region Azure AI Gateway that:

- **Private Network Integration**: APIM integrated with dedicated VNet for private backend access
- **Private Endpoint Connectivity**: AI Foundry accounts accessible only via private endpoints
- **Multi-Region Resilience**: Deploys Azure AI Foundry accounts across 3 regions with automatic failover
- **Priority-Based Routing**: Routes requests to regional backends based on configurable priority (1→2→3)
- **Circuit Breaker Pattern**: Opens circuit for 10 seconds on a single 429 error, preventing cascading failures
- **Dual API Support**: Supports both Azure OpenAI native format (`/openai/deployments/*`) and OpenAI v1 compatible format (`/v1/*`)
- **Managed Identity Authentication**: Uses Azure managed identity for secure, keyless authentication to AI Foundry
- **Comprehensive Monitoring**: Application Insights integration with token usage tracking
- **Network Security**: NSG rules with phased hardening for least-privilege outbound access

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                          API Consumer                            │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Azure API Management (APIM)                    │
│                  (West Europe - StandardV2)                      │
│                  VNet Integrated (External Mode)                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  APIs:                                                    │  │
│  │  • /openai/deployments/* (Azure OpenAI format)           │  │
│  │  • /v1/* (OpenAI compatible format)                      │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Backend Pools (per model):                              │  │
│  │  • pool-gpt-4o-mini-2024-07-18                           │  │
│  │    - Priority 1: Sweden Central                          │  │
│  │    - Priority 1: France Central                          │  │
│  │    - Priority 2: West Europe                             │  │
│  │  Circuit Breaker: 1x 429 → 10s timeout                   │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────┬───────────────────────┬───────────────────────┬─────────┘
        │ Private Endpoint      │ Private Endpoint      │ Private Endpoint
        │ (10.50.1.x)          │ (10.50.1.x)          │ (10.50.1.x)
        ▼                       ▼                       ▼
┌───────────────┐      ┌───────────────┐      ┌───────────────┐
│ AI Foundry    │      │ AI Foundry    │      │ AI Foundry    │
│ West Europe   │      │ Sweden Central│      │ France Central│
│ (Priority 2)  │      │ (Priority 1)  │      │ (Priority 1)  │
│ Public: ❌    │      │ Public: ❌    │      │ Public: ❌    │
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

Network Architecture:
┌──────────────────────────────────────────────────────────────┐
│ VNet: vnet-acc-kpn (10.50.0.0/20)                            │
│ ┌────────────────────────────────────────────────────────┐   │
│ │ snet-apim (10.50.0.0/27)                               │   │
│ │ • NSG: allow Storage, AzureMonitor, CognitiveServices  │   │
│ │ • Delegation: Microsoft.Web/serverFarms                │   │
│ │ • APIM StandardV2 integrated here                      │   │
│ └────────────────────────────────────────────────────────┘   │
│ ┌────────────────────────────────────────────────────────┐   │
│ │ snet-pep-ai (10.50.1.0/24)                             │   │
│ │ • Private Endpoints for AI Foundry accounts            │   │
│ │ • Private DNS: privatelink.cognitiveservices.azure.com │   │
│ └────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

## 🚀 Features

### Private Network Integration (NEW)
- APIM integrated into dedicated VNet with outbound connectivity
- Private endpoints for all AI Foundry accounts (West Europe, Sweden Central, France Central)
- Private DNS zone (`privatelink.cognitiveservices.azure.com`) for internal name resolution
- Network Security Groups (NSG) with phased hardening:
  - Phase 1: Service tag-based rules for Azure Storage, Monitor, and Cognitive Services
  - Phase 2: IP-based rules restricting to specific private endpoint IPs
- Public network access disabled on all AI Foundry accounts
- Subnet delegation to `Microsoft.Web/serverFarms` for APIM StandardV2

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
  - Virtual Network with 2 subnets (minimum /27 for APIM, /24 for private endpoints)
  - Private Endpoints (3 for AI Foundry accounts)
  - Private DNS Zone
  - Log Analytics workspace
- Azure CLI installed ([Install guide](https://docs.microsoft.com/cli/azure/install-azure-cli))
- PowerShell 7+ (for deployment script)
- Appropriate Azure permissions:
  - Contributor role on target subscription/resource group
  - User Access Administrator (for RBAC assignments)
  - Network Contributor (for VNet, subnet, NSG, private endpoint creation)

## 🛠️ Deployment

### 1. Configure Parameters

Edit `infra/main.dev.parameters.bicepparam` (or your environment-specific parameter file):

```bicep
using 'main.bicep'

param environment = 'dev'
param suffix = 'genaishared'
param rgLocation = 'westeurope'
param apimPublisherEmail = 'your-email@example.com'
param apimPublisherName = 'Your Organization'
param apimSku = 'StandardV2'

# Network Configuration (NEW)
param vnetName = 'vnet-acc-kpn'
param createNewVnet = true
param vnetAddressPrefixes = ['10.50.0.0/20']
param apimSubnetPrefix = '10.50.0.0/27'
param pepSubnetPrefix = '10.50.1.0/24'
param virtualNetworkType = 'External'
param enforcePrivateAccess = true
param allowedCognitivePrivateEndpointIps = []  # Phase 2: Add specific IPs

param openAILocations = [
  {
    name: 'westeurope'
    abbreviation: 'we'
    deployments: [
      {
        deploymentName: 'gpt-4o-mini-2024-07-18'
        name: 'gpt-4o-mini'
        version: '2024-07-18'
        format: 'OpenAI'
        skuName: 'DataZoneStandard'
        skuCapacity: 10
        priority: 2
      }
    ]
  }
  {
    name: 'swedencentral'
    abbreviation: 'sc'
    deployments: [
      {
        deploymentName: 'gpt-4o-mini-2024-07-18'
        name: 'gpt-4o-mini'
        version: '2024-07-18'
        format: 'OpenAI'
        skuName: 'DataZoneStandard'
        skuCapacity: 10
        priority: 1
      }
    ]
  }
  {
    name: 'francecentral'
    abbreviation: 'fc'
    deployments: [
      {
        deploymentName: 'gpt-4o-mini-2024-07-18'
        name: 'gpt-4o-mini'
        version: '2024-07-18'
        format: 'OpenAI'
        skuName: 'DataZoneStandard'
        skuCapacity: 10
        priority: 1
      }
    ]
  }
]
```

### 2. Update Resource Group Configuration

Edit `infra/resourcegroup.config.json`:

```json
{
  "resourceGroupNames": ["rg-kpn-apimv2"],
  "tags": {
    "ApplicationName": "GenAIGatewayV2",
    "BusinessUnit": "AI CoE"
  }
}
```

### 3. Run Deployment

```powershell
# Login to Azure
az login

# Validate deployment (what-if)
cd infra
az deployment group what-if --resource-group rg-kpn-apimv2 --template-file main.bicep --parameters main.dev.parameters.bicepparam

# Deploy infrastructure
az deployment group create --resource-group rg-kpn-apimv2 --template-file main.bicep --parameters main.dev.parameters.bicepparam --name "deploy-apim-private-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
```

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
├── plan.md                             # Detailed deployment plan
├── README.md                           # This file
│
├── infra/                              # Infrastructure as Code
│   ├── main.bicep                      # Main orchestration template
│   ├── main.dev.parameters.bicepparam  # Environment parameters
│   ├── main.json                       # Compiled ARM template
│   ├── resourcegroup.config.json       # Resource group configuration
│   │
│   ├── specs/                          # Architecture specifications
│   │   ├── apim-vnet-integration-spec.md  # VNet integration spec (IMPLEMENTED)
│   │
│   └── modules/                        # Bicep modules
│       ├── ai-foundry.bicep           # AI Foundry account & project
│       ├── ai-foundry-rbac.bicep      # RBAC role assignments
│       ├── ai-private-endpoints.bicep # Private endpoints (NEW)
│       ├── apim.bicep                 # API Management service (VNet integrated)
│       ├── apim-backend-pools.bicep   # Backend pool configuration
│       ├── apim-config.bicep          # Named values configuration
│       ├── apim-managed-identity.bicep # Managed identity configuration
│       ├── apim-policies.bicep        # Policy attachment
│       ├── app-insights.bicep         # Application Insights
│       ├── custom-table.bicep         # Custom table for logs
│       ├── data-collection-endpoint.bicep # Data collection endpoint
│       ├── data-collection-rule.bicep # Data collection rule
│       ├── log-analytics.bicep        # Log Analytics workspace
│       ├── model-deployments.bicep    # Model deployments & backends
│       └── network.bicep              # VNet, subnets, NSG, DNS (NEW)
│
├── apim-policies/                      # APIM policy definitions
│   ├── aoai-policy.xml                # Azure OpenAI format policy
│   └── oaiv1-policy.xml               # OpenAI v1 format policy
│
├── openapi/                            # OpenAPI specifications
│   ├── azure-openai-2024-02-01.json   # Azure OpenAI API spec
│   └── openai-v1.json                 # OpenAI v1 API spec
│
├── queries/                            # KQL queries
│   └── token-metrics.kql              # Token usage metrics
│
└── tests/                              # Test scripts
    ├── README.md                       # Testing documentation
    ├── requirements.txt                # Test dependencies
    ├── test_azure_openai.py           # Azure OpenAI format tests
    ├── test_models_v1.py              # Models endpoint tests
    └── test_openai_v1.py              # OpenAI v1 format tests
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
4. **Private Network Access**: AI Foundry accounts accessible only via private endpoints
5. **Public Access Disabled**: All AI Foundry accounts have `publicNetworkAccess: Disabled`
6. **Network Segmentation**: Dedicated subnets for APIM and private endpoints
7. **NSG Protection**: Network Security Group rules enforce least-privilege outbound access
8. **Private DNS**: Internal name resolution via `privatelink.cognitiveservices.azure.com`
9. **Policy-Based Auth**: Authentication logic centralized in APIM policies
10. **VNet Integration**: APIM integrated in External mode (gateway public, backends private)

### Network Security Group Rules

**Phase 1 (Current - Service Tag Based):**
- Priority 100: Allow outbound to Azure Storage (TCP 443)
- Priority 110: Allow outbound to Azure Monitor (TCP 443)
- Priority 120: Allow outbound to Cognitive Services Frontend (TCP 443)

**Phase 2 (Future - IP Based Hardening):**
- Replace service tag rules with specific private endpoint IP addresses
- Capture IPs: `az network private-endpoint list -g <rg> --query "[].customDnsConfigs[0].ipAddresses[0]"`
- Update `allowedCognitivePrivateEndpointIps` parameter and redeploy

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
az apim backend list --resource-group rg-kpn-apimv2 --service-name apim-dev-genaishared-xxxxx

# Show backend pool configuration
az apim backend show --resource-group rg-kpn-apimv2 --service-name apim-dev-genaishared-xxxxx --backend-id pool-gpt-4o-mini-2024-07-18
```

### Verify Private Network Configuration

```powershell
# Check VNet and subnets
az network vnet show --resource-group rg-kpn-apimv2 --name vnet-acc-kpn

# List private endpoints
az network private-endpoint list --resource-group rg-kpn-apimv2 -o table

# Verify private endpoint IPs
az network private-endpoint list --resource-group rg-kpn-apimv2 --query "[].{Name:name, IP:customDnsConfigs[0].ipAddresses[0]}" -o table

# Check NSG rules
az network nsg show --resource-group rg-kpn-apimv2 --name nsg-snet-apim

# Verify private DNS zone
az network private-dns zone show --resource-group rg-kpn-apimv2 --name privatelink.cognitiveservices.azure.com

# List DNS records
az network private-dns record-set a list --resource-group rg-kpn-apimv2 --zone-name privatelink.cognitiveservices.azure.com -o table
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
- **Solution**: Ensure deployment name matches backend pool name (e.g., `pool-gpt-4o-mini-2024-07-18`)

**Issue**: 429 errors not triggering circuit breaker
- **Solution**: Check backend pool configuration has correct trip threshold (should be 1)

**Issue**: Connection timeout to AI Foundry
- **Solution**: 
  - Verify private endpoints are in `Succeeded` state
  - Check NSG rules allow outbound to `CognitiveServicesFrontend` or specific IPs
  - Confirm private DNS zone is linked to VNet
  - Verify `publicNetworkAccess: Disabled` on AI Foundry accounts

**Issue**: DNS resolution fails
- **Solution**:
  - Check private DNS zone link: `az network private-dns link vnet list`
  - Verify A records exist for each AI Foundry account
  - APIM uses VNet DNS automatically in External mode

**Issue**: Deployment fails with "VNet not found"
- **Solution**: Set `createNewVnet: true` in parameters if VNet doesn't exist

**Issue**: Deployment fails with "API version not supported for privateDnsZones"
- **Solution**: Ensure `network.bicep` uses API version `2024-06-01` for Private DNS resources

## 📚 Additional Resources

- [Azure API Management Documentation](https://docs.microsoft.com/azure/api-management/)
- [Azure API Management VNet Integration](https://learn.microsoft.com/azure/api-management/integrate-vnet-outbound)
- [Azure OpenAI Service Documentation](https://docs.microsoft.com/azure/cognitive-services/openai/)
- [Azure AI Foundry Documentation](https://docs.microsoft.com/azure/ai-services/ai-foundry/)
- [Backend Circuit Breaker Pattern](https://docs.microsoft.com/azure/api-management/backends)
- [Azure Private Endpoint Documentation](https://docs.microsoft.com/azure/private-link/private-endpoint-overview)
- [Azure Private DNS Zones](https://docs.microsoft.com/azure/dns/private-dns-overview)
- [VNet Integration Spec](infra/specs/apim-vnet-integration-spec.md) - Detailed implementation spec (✅ Implemented)

## 📝 License

This project is licensed under the MIT License.

## 🤝 Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## 📧 Support

For issues and questions:
1. Check the [Troubleshooting](#-troubleshooting) section
2. Review Application Insights logs
3. Open an issue in this repository
