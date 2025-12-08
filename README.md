# Azure AI Gateway v2

A multi-region Azure AI Gateway implementation using Azure API Management (APIM) with priority-based backend pools, circuit breaker patterns, Application Gateway WAF ingress, and comprehensive monitoring for Azure OpenAI deployments.

## 🏗️ Architecture Overview

This solution creates a resilient, multi-region Azure AI Gateway that:

- **Application Gateway WAF Ingress**: Public HTTPS entry point with TLS termination and Web Application Firewall
- **APIM Gateway Private Endpoint**: APIM gateway accessible via private endpoint with private DNS integration
- **Private Network Integration**: APIM integrated with dedicated VNet for private backend access
- **Private Endpoint Connectivity**: AI Foundry accounts accessible only via private endpoints
- **Multi-Region Resilience**: Deploys Azure AI Foundry accounts across 3 regions with automatic failover
- **Priority-Based Routing**: Routes requests to regional backends based on configurable priority (1→2→3)
- **Circuit Breaker Pattern**: Opens circuit for 10 seconds on a single 429 error, preventing cascading failures
- **Dual API Support**: Supports both Azure OpenAI native format (`/openai/deployments/*`) and OpenAI v1 compatible format (`/v1/*`)
- **Managed Identity Authentication**: Uses Azure managed identity for secure, keyless authentication to AI Foundry
- **Comprehensive Monitoring**: Application Insights integration with token usage tracking and consumer identity
- **Network Security**: NSG rules with phased hardening for least-privilege outbound access

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                       Internet / Clients                         │
└───────────────────────────────┬─────────────────────────────────┘
                                │ HTTPS (443)
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│              Azure Application Gateway (WAF_v2)                  │
│                    (West Europe - Public IP)                     │
│                  TLS Termination (Self-signed)                   │
│  DNS: appgw-{suffix}.westeurope.cloudapp.azure.com              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  • Public HTTPS Listener (port 443)                       │  │
│  │  • Certificate from Key Vault                             │  │
│  │  • Backend: APIM Gateway hostname                        │  │
│  │  • Health Probe: /status-0123456789abcdef                │  │
│  │  • Host Header Forwarding: Enabled                       │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────────┬─────────────────────────────────┘
                                │ Private DNS Override
                                │ apim-{env}-{suffix}.azure-api.net
                                │ → 10.31.193.14 (Private Endpoint IP)
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│         APIM Gateway Private Endpoint (pep-apim-gateway)         │
│                    Private DNS Integration                       │
│              privatelink.azure-api.net (10.31.193.14)           │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Azure API Management (APIM)                    │
│                  (West Europe - StandardV2)                      │
│                  VNet Integrated (External Mode)                 │
│                  Public FQDN with Private DNS Override          │
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
                    │ • Custom Token Metrics│
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
│ ┌────────────────────────────────────────────────────────┐   │
│ │ snet-pep-apim (10.31.193.0/24)                         │   │
│ │ • Private Endpoint for APIM Gateway                    │   │
│ │ • Private DNS: privatelink.azure-api.net               │   │
│ └────────────────────────────────────────────────────────┘   │
│ ┌────────────────────────────────────────────────────────┐   │
│ │ snet-appgw (10.31.192.0/24)                            │   │
│ │ • Application Gateway (WAF_v2)                         │   │
│ │ • Public IP with DNS label                             │   │
│ └────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘

Key Vault Integration:
┌──────────────────────────────────────────────────────────────┐
│ Azure Key Vault (kv-apim-{suffix})                           │
│ • Certificate: appgw-cert (Self-signed, 2 years)             │
│ • RBAC: User (Admin), APIM MI (Secrets User)                 │
│ • Used by: Application Gateway for TLS termination           │
└──────────────────────────────────────────────────────────────┘
```

## 🚀 Features

### Application Gateway WAF Ingress (NEW)
- Public HTTPS entry point with WAF_v2 SKU
- TLS termination using certificates from Azure Key Vault
- Backend health probes monitoring APIM gateway availability
- Host header forwarding to APIM backend (preserves original hostname)
- Self-signed certificates for non-production environments
- Automatic DNS label for public IP (`appgw-{suffix}.{region}.cloudapp.azure.com`)

### APIM Gateway Private Endpoint (NEW)
- Private endpoint for APIM gateway service
- Private DNS zone integration (`privatelink.azure-api.net`)
- APIM public FQDN resolves to private IP within VNet
- Approved private endpoint connection
- Optional public network access disable capability
- Application Gateway accesses APIM via private endpoint

### Private Network Integration
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
- Azure OpenAI token metrics emitted for usage tracking with dimensions:
  - **API ID**: Which API endpoint was called
  - **Deployment**: Model deployment name (e.g., "gpt-4o-mini-2024-07-18")
  - **Consumer**: Service Principal/User name (extracted from JWT token) *
  - **Streaming**: Whether streaming was enabled (true/false)
  - **Request ID**: Correlation ID for tracing
- Request/response logging with deployment tracking
- Token field mapping: `prompt_tokens` (input), `completion_tokens` (output), `total_tokens`

\* Consumer identity tracking requires Entra ID authentication and Graph API integration (optional)

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

# Network Configuration
param vnetName = 'vnet-acc-kpn'
param createNewVnet = true
param vnetAddressPrefixes = ['10.50.0.0/20']
param apimSubnetPrefix = '10.50.0.0/27'
param pepSubnetPrefix = '10.50.1.0/24'
param virtualNetworkType = 'External'
param enforcePrivateAccess = true
param allowedCognitivePrivateEndpointIps = []  # Phase 2: Add specific IPs

# APIM Gateway Private Endpoint & Application Gateway (NEW)
param enableApimGatewayPrivateEndpoint = true  # Enable private endpoint + App Gateway
param apimGatewayPepSubnetPrefix = '10.31.193.0/24'
param appGatewaySubnetPrefix = '10.31.192.0/24'
param disableApimPublicAccess = false  # Set to true to disable APIM public access
param enableDeveloperPortal = false    # Developer portal disabled by default for StandardV2

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

# (Optional) Generate self-signed certificate for Application Gateway
$dnsName = "appgw-{suffix}.westeurope.cloudapp.azure.com"
$certPassword = "AppGwCert2025!"
New-SelfSignedCertificate -DnsName $dnsName -CertStoreLocation "Cert:\CurrentUser\My" -KeyExportPolicy Exportable -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider" -NotAfter (Get-Date).AddYears(2)

# Export certificate (get thumbprint from previous command)
$thumbprint = "YOUR_CERT_THUMBPRINT"
$certPath = ".\appgw-cert.pfx"
$pwd = ConvertTo-SecureString -String $certPassword -Force -AsPlainText
Export-PfxCertificate -Cert "Cert:\CurrentUser\My\$thumbprint" -FilePath $certPath -Password $pwd

# Upload certificate to Key Vault
az keyvault certificate import --vault-name "kv-apim-{suffix}" --name "appgw-cert" --file $certPath --password $certPassword
```

### 4. Verify Deployment

The deployment script outputs key information:

```
Deployment Outputs:
==================
APIM Gateway URL: https://apim-acc-genaishared-xxxxx.azure-api.net
Application Gateway URL: https://appgw-xxxxx.westeurope.cloudapp.azure.com (if enabled)
APIM Name: apim-acc-genaishared-xxxxx
Managed Identity Client ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
Log Analytics Workspace ID: /subscriptions/.../workspaces/law-acc-genaishared
APIM Gateway Private Endpoint IP: 10.31.193.14 (if enabled)
Key Vault Name: kv-apim-{suffix} (if Application Gateway enabled)
```

**Testing the flow:**
- Public clients connect to Application Gateway public IP/DNS
- Application Gateway resolves APIM FQDN to private IP (10.31.193.14) via private DNS
- APIM processes request and routes to AI Foundry via private endpoints
- All backend communication stays within the private network

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
# Configure endpoint in test scripts
# For Application Gateway (recommended):
# Set APIM_ENDPOINT = "https://appgw-{suffix}.westeurope.cloudapp.azure.com"
# Set VERIFY_SSL = False (for self-signed certificates)

# For direct APIM access:
# Set APIM_ENDPOINT = "https://apim-{env}-{suffix}.azure-api.net"
# Set VERIFY_SSL = True

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
│   │   ├── apim-vnet-integration-spec.md      # VNet integration spec (IMPLEMENTED)
│   │   └── apim-private-standardv2-spec.md    # APIM Gateway PE + App Gateway spec (IMPLEMENTED)
│   │
│   └── modules/                        # Bicep modules
│       ├── ai-foundry.bicep                    # AI Foundry account & project
│       ├── ai-foundry-rbac.bicep               # RBAC role assignments
│       ├── ai-private-endpoints.bicep          # AI Foundry private endpoints
│       ├── apim.bicep                          # API Management service (VNet integrated)
│       ├── apim-backend-pools.bicep            # Backend pool configuration
│       ├── apim-config.bicep                   # Named values configuration
│       ├── apim-managed-identity.bicep         # Managed identity configuration
│       ├── apim-policies.bicep                 # Policy attachment
│       ├── apim-gateway-ingress.bicep          # APIM Gateway ingress orchestration (NEW)
│       ├── apim-gateway-private-endpoint.bicep # APIM Gateway private endpoint (NEW)
│       ├── app-gateway.bicep                   # Application Gateway (NEW)
│       ├── app-insights.bicep                  # Application Insights
│       ├── custom-table.bicep                  # Custom table for logs
│       ├── data-collection-endpoint.bicep      # Data collection endpoint
│       ├── data-collection-rule.bicep          # Data collection rule
│       ├── key-vault.bicep                     # Key Vault for certificates (NEW)
│       ├── log-analytics.bicep                 # Log Analytics workspace
│       ├── model-deployments.bicep             # Model deployments & backends
│       └── network.bicep                       # VNet, subnets, NSG, DNS
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
4. **Token Metrics**: Emits usage metrics to Application Insights with dimensions:
   - API ID, Deployment, Streaming, Request ID
   - (Optional) Consumer identity from JWT tokens with Graph API lookup
5. **Retry Logic**: 2 retries with 1-second intervals on 429 errors

**Enhanced Consumer Tracking (Optional):**
- Validates Entra ID JWT tokens
- Extracts Service Principal display name via Graph API
- Caches identity lookups for 8 hours (28800 seconds)
- Adds Consumer dimension to telemetry (e.g., "KPN-CCT-CLIENT-PRD")
- Sets `X-Consumer` header for downstream services

### Named Values

APIM named values (configured in `modules/apim-config.bicep`):

- `managed-identity-client-id`: Client ID of the APIM managed identity

**For enhanced consumer tracking (optional):**
- `aad-tenant`: Entra ID tenant ID
- `apim-audience`: APIM application ID (audience claim in JWT)

**Required Graph API Permissions (for consumer tracking):**
- APIM Managed Identity needs `ServicePrincipal.Read.All` (Application permission)

## 📊 Monitoring

### Application Insights

Token usage metrics are automatically captured with the following dimensions:
- **Prompt tokens** (`prompt_tokens`): Input tokens consumed
- **Completion tokens** (`completion_tokens`): Output tokens generated
- **Total tokens** (`total_tokens`): Sum of prompt + completion
- **Model deployment name**: Specific model version (e.g., "gpt-4o-mini-2024-07-18")
- **Request ID**: Unique correlation ID
- **Streaming flag**: Whether streaming was enabled (true/false)
- **Consumer** (optional): Service Principal/User display name from JWT

### Query Usage Metrics

Use the provided KQL query (`queries/token-metrics.kql`) in Log Analytics:

```kql
customMetrics
| where name startswith "AzureOpenAI"
| extend Deployment = tostring(customDimensions["Deployment"])
| extend Streaming = tostring(customDimensions["Streaming"])
| extend Consumer = tostring(customDimensions["Consumer"])  // If enabled
| summarize 
    TotalRequests = count(),
    AvgPromptTokens = avg(valueMax),
    AvgCompletionTokens = avg(valueMax)
    by Deployment, Streaming, Consumer
```

## 🔒 Security Considerations

1. **No API Keys**: All authentication uses Azure managed identity
2. **RBAC**: Minimal permissions granted (Cognitive Services OpenAI User, Azure AI Developer)
3. **Project-Level Scoping**: RBAC assignments scoped to individual AI Foundry projects
4. **Private Network Access**: AI Foundry accounts accessible only via private endpoints
5. **Public Access Disabled**: All AI Foundry accounts have `publicNetworkAccess: Disabled`
6. **Network Segmentation**: Dedicated subnets for APIM, private endpoints, and Application Gateway
7. **NSG Protection**: Network Security Group rules enforce least-privilege outbound access
8. **Private DNS**: Internal name resolution via private DNS zones
9. **Policy-Based Auth**: Authentication logic centralized in APIM policies
10. **VNet Integration**: APIM integrated in External mode (gateway public, backends private)
11. **Application Gateway WAF**: Web Application Firewall protects public entry point
12. **APIM Gateway Private Endpoint**: APIM gateway accessible via private endpoint only (optional)
13. **Key Vault Integration**: Certificates stored securely in Azure Key Vault
14. **TLS Termination**: End-to-end encryption with TLS 1.2/1.3
15. **JWT Validation**: Optional Entra ID token validation for consumer identity tracking

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

# List all private endpoints
az network private-endpoint list --resource-group rg-kpn-apimv2 -o table

# Verify private endpoint IPs
az network private-endpoint list --resource-group rg-kpn-apimv2 --query "[].{Name:name, IP:customDnsConfigs[0].ipAddresses[0]}" -o table

# Check NSG rules
az network nsg show --resource-group rg-kpn-apimv2 --name nsg-snet-apim

# Verify private DNS zones
az network private-dns zone list --resource-group rg-kpn-apimv2 -o table

# List DNS records for AI Foundry
az network private-dns record-set a list --resource-group rg-kpn-apimv2 --zone-name privatelink.cognitiveservices.azure.com -o table

# List DNS records for APIM Gateway (if private endpoint enabled)
az network private-dns record-set a list --resource-group rg-kpn-apimv2 --zone-name privatelink.azure-api.net -o table

# Verify Application Gateway backend health
az network application-gateway show-backend-health --resource-group rg-kpn-apimv2 --name appgw-{suffix}

# Check Key Vault certificate
az keyvault certificate show --vault-name kv-apim-{suffix} --name appgw-cert
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

**Issue**: 502 Bad Gateway from Application Gateway
- **Solution**:
  - Check Application Gateway backend health: `az network application-gateway show-backend-health`
  - Verify `pickHostNameFromBackendAddress: true` in backend HTTP settings
  - Confirm APIM private endpoint is approved and DNS resolution works
  - Check Application Gateway subnet has route to APIM private endpoint subnet

**Issue**: Certificate errors from Application Gateway
- **Solution**:
  - Verify certificate uploaded to Key Vault: `az keyvault certificate show`
  - Check APIM managed identity has `Key Vault Secrets User` role
  - Confirm certificate DNS name matches Application Gateway DNS label
  - For testing, use `VERIFY_SSL = False` in test scripts with self-signed certs

**Issue**: Application Gateway timeout on long-running requests
- **Solution**:
  - Increase backend HTTP settings `requestTimeout` (default 30s) in `app-gateway.bicep`
  - Use streaming mode for models with slow response times
  - Monitor Application Gateway metrics for timeout patterns

**Issue**: DNS resolution fails
- **Solution**:
  - Check private DNS zone link: `az network private-dns link vnet list`
  - Verify A records exist for each AI Foundry account and APIM gateway
  - APIM uses VNet DNS automatically in External mode
  - Application Gateway should resolve APIM FQDN to private IP within VNet

**Issue**: Deployment fails with "VNet not found"
- **Solution**: Set `createNewVnet: true` in parameters if VNet doesn't exist

**Issue**: Deployment fails with "API version not supported for privateDnsZones"
- **Solution**: Ensure `network.bicep` uses API version `2024-06-01` for Private DNS resources

**Issue**: APIM public access disable breaks external access
- **Solution**: 
  - Only disable public access after Application Gateway + private endpoint is deployed and tested
  - Ensure `enableApimGatewayPrivateEndpoint = true` before setting `disableApimPublicAccess = true`
  - Verify all clients route through Application Gateway, not direct to APIM

**Issue**: Consumer identity not appearing in metrics
- **Solution**:
  - Verify Entra ID JWT validation is configured in APIM policies
  - Check APIM managed identity has `ServicePrincipal.Read.All` permission on Graph API
  - Confirm named values `aad-tenant` and `apim-audience` are set correctly
  - Review Application Insights customMetrics for Consumer dimension

## 📚 Additional Resources

- [Azure API Management Documentation](https://docs.microsoft.com/azure/api-management/)
- [Azure API Management VNet Integration](https://learn.microsoft.com/azure/api-management/integrate-vnet-outbound)
- [Azure Application Gateway Documentation](https://docs.microsoft.com/azure/application-gateway/)
- [Application Gateway with APIM](https://learn.microsoft.com/azure/api-management/api-management-howto-integrate-internal-vnet-appgateway)
- [Azure OpenAI Service Documentation](https://docs.microsoft.com/azure/cognitive-services/openai/)
- [Azure AI Foundry Documentation](https://docs.microsoft.com/azure/ai-services/ai-foundry/)
- [Backend Circuit Breaker Pattern](https://docs.microsoft.com/azure/api-management/backends)
- [Azure Private Endpoint Documentation](https://docs.microsoft.com/azure/private-link/private-endpoint-overview)
- [Azure Private DNS Zones](https://docs.microsoft.com/azure/dns/private-dns-overview)
- [Azure Key Vault Certificates](https://docs.microsoft.com/azure/key-vault/certificates/)
- [VNet Integration Spec](infra/specs/apim-vnet-integration-spec.md) - AI Foundry private endpoints (✅ Implemented)
- [APIM Private StandardV2 Spec](infra/specs/apim-private-standardv2-spec.md) - APIM Gateway PE + App Gateway (✅ Implemented)

## 📝 License

This project is licensed under the MIT License.

## 🤝 Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## 📧 Support

For issues and questions:
1. Check the [Troubleshooting](#-troubleshooting) section
2. Review Application Insights logs
3. Open an issue in this repository
