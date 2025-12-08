# APIM Gateway Private Endpoint + Application Gateway Implementation

## Overview

This implementation adds private inbound access to API Management (APIM) using a gateway private endpoint combined with Azure Application Gateway for public-facing TLS termination and WAF protection.

## Architecture

```
Internet → App Gateway (Public) → APIM Gateway PE (Private) → APIM (VNet) → AI Services PEs (Private) → AI Foundry Accounts
```

## Files Created/Modified

### New Modules

1. **`infra/modules/apim-gateway-private-endpoint.bicep`**
   - Creates APIM gateway private endpoint
   - Targets APIM service with `Gateway` group ID
   - Integrates with `privatelink.azure-api.net` DNS zone
   - Outputs private IP address for App Gateway backend

2. **`infra/modules/app-gateway.bicep`**
   - Deploys Application Gateway WAF_v2 SKU
   - Public IP with FQDN for external access
   - Backend pool pointing to APIM gateway PE private IP
   - HTTPS listener with Key Vault certificate integration
   - HTTP→HTTPS redirect rule
   - Health probe targeting APIM `/status-0123456789abcdef`
   - WAF in Prevention mode (OWASP 3.2)
   - Autoscale 2-10 instances

3. **`infra/modules/apim-gateway-ingress.bicep`**
   - Wrapper module orchestrating APIM PE + App Gateway deployment
   - Ensures proper dependency: APIM PE deployed first, then App Gateway
   - Solves Bicep conditional module output access issue
   - Consolidates outputs for both components

### Modified Modules

4. **`infra/modules/network.bicep`**
   - Added parameters:
     - `enableApimGatewayPrivateEndpoint` (bool, default false)
     - `apimPeSubnetPrefix` (default '10.50.2.0/28')
     - `appGwSubnetPrefix` (default '10.50.3.0/27')
   - Added NSG `nsgAppGw`:
     - Inbound: Internet (443/80), GatewayManager health probes (65200-65535)
     - Outbound: APIM PE subnet (443), AzureMonitor (443)
   - Added conditional subnets (created only when feature flag enabled):
     - `apimPeSubnetNew/Existing` - /28 for APIM gateway PE (policies disabled)
     - `appGwSubnetNew/Existing` - /27 for App Gateway (with NSG)
   - Sequential dependency chain to prevent locks:
     - AI PE subnet → APIM PE subnet → App Gateway subnet
   - Added private DNS zone `privatelink.azure-api.net` with VNet link
   - Added outputs: `apimPeSubnetId`, `appGwSubnetId`, `privateDnsZoneApimId`

5. **`infra/main.bicep`**
   - Added parameters:
     - `enableApimGatewayPrivateEndpoint` (bool, default false)
     - `apimPeSubnetPrefix`, `appGwSubnetPrefix`
     - `keyVaultId` (required when feature enabled)
     - `appGwCertificateName` (default 'appgw-cert')
   - Updated network module call with new parameters
   - Added conditional module call to `apim-gateway-ingress.bicep`
   - Updated deployment summary output with feature status

6. **`infra/main.dev.parameters.bicepparam`**
   - Added parameter values:
     - `enableApimGatewayPrivateEndpoint = false` (disabled by default)
     - `apimPeSubnetPrefix = '10.50.2.0/28'`
     - `appGwSubnetPrefix = '10.50.3.0/27'`
     - `keyVaultId = ''` (empty when feature disabled)
     - `appGwCertificateName = 'appgw-cert'`

## Network Topology

### Subnets (when feature enabled)

| Subnet | CIDR | Purpose | Special Config |
|--------|------|---------|----------------|
| `snet-apim` | 10.50.0.0/27 | APIM outbound VNet integration | Delegated to Microsoft.Web/serverFarms |
| `snet-pep-ai` | 10.50.1.0/24 | AI services private endpoints | PE policies disabled |
| `snet-pep-apim` | 10.50.2.0/28 | APIM gateway private endpoint | PE policies disabled |
| `snet-appgw` | 10.50.3.0/27 | Application Gateway | NSG attached |

### NSG Rules (App Gateway Subnet)

**Inbound:**
- Priority 100: Allow Internet → 443, 80
- Priority 110: Allow GatewayManager → 65200-65535 (health probes)

**Outbound:**
- Priority 100: Allow → APIM PE subnet (10.50.2.0/28) on 443
- Priority 110: Allow → AzureMonitor on 443

## Deployment Sequence

The implementation ensures proper dependency ordering to avoid Azure Resource Manager locks:

1. **Network Module** (includes subnets created sequentially)
   - AI PE subnet
   - APIM PE subnet (depends on AI PE)
   - App Gateway subnet (depends on APIM PE)
   - Private DNS zones (AI + APIM)

2. **APIM Service** (depends on network)

3. **APIM Gateway Ingress Module** (conditional, depends on APIM)
   - 3a. APIM Gateway Private Endpoint
   - 3b. Application Gateway (depends on 3a for private IP)

4. **AI Foundry + Model Deployments** (existing flow)

5. **Backend Pools + Policies** (existing flow)

## Feature Flag Control

The feature is **disabled by default** via `enableApimGatewayPrivateEndpoint = false`. When disabled:
- No new subnets created
- No APIM gateway PE deployed
- No Application Gateway deployed
- Existing deployment flow unchanged

To enable:
1. Set `enableApimGatewayPrivateEndpoint = true`
2. Provide `keyVaultId` (must contain certificate secret)
3. Optionally customize subnet CIDRs via `apimPeSubnetPrefix` and `appGwSubnetPrefix`

## Prerequisites for Enablement

1. **Key Vault** with:
   - TLS certificate stored as secret (default name: `appgw-cert`)
   - Network access allowing deployment subnet
   - RBAC role assignment: Managed Identity needs `Key Vault Secrets User` role

2. **Managed Identity** (already exists in deployment):
   - Used by both APIM and App Gateway
   - Requires `Key Vault Secrets User` role assignment on Key Vault

3. **Virtual Network** with available address space:
   - /28 for APIM PE (16 IPs)
   - /27 for App Gateway (32 IPs)

## Post-Deployment Steps

Per spec Section 12.1.9, after deployment:

1. **Approve Private Endpoint Connection**
   ```powershell
   az network private-endpoint-connection approve `
     --id <apim-pe-connection-id> `
     --description "Approved for production use"
   ```

2. **Validate DNS Resolution**
   ```powershell
   nslookup <apim-name>.azure-api.net
   # Should resolve to APIM PE private IP (10.50.2.x)
   ```

3. **Test App Gateway → APIM Connectivity**
   ```powershell
   # Access via App Gateway public FQDN
   curl https://<appgw-fqdn>/status-0123456789abcdef
   ```

4. **(Optional) Disable APIM Public Access**
   - Only after validating PE connectivity
   - Update APIM resource with `publicNetworkAccess: Disabled`
   - Requires coordination with spec Section 12.1.5 ordering rule

## Validation Commands

```powershell
# Bicep compilation check
az bicep build --file infra/main.bicep

# What-if deployment (dry run)
az deployment group what-if `
  --resource-group <rg-name> `
  --template-file infra/main.bicep `
  --parameters infra/main.dev.parameters.bicepparam

# Actual deployment
az deployment group create `
  --resource-group <rg-name> `
  --template-file infra/main.bicep `
  --parameters infra/main.dev.parameters.bicepparam `
  --mode Incremental
```

## Dependency Lock Prevention

The implementation uses explicit sequential dependencies to prevent Azure RM locks:

- **Subnet creation**: AI PE → APIM PE → App Gateway (via `dependsOn` in conditional resources)
- **Module orchestration**: Network → APIM → APIM Gateway Ingress wrapper
- **Nested modules**: APIM PE → App Gateway (within ingress wrapper)

This ensures subnets are not created in parallel and module dependencies are tracked correctly.

## Outputs

When feature is **enabled**, deployment summary includes:
```json
{
  "apim": {
    "privateEndpointEnabled": true
  },
  "applicationGateway": {
    "enabled": true
  }
}
```

When **disabled**:
```json
{
  "apim": {
    "privateEndpointEnabled": false
  },
  "applicationGateway": {
    "enabled": false
  }
}
```

## Rollback Plan

Per spec Section 12.1.10, to rollback:

1. Disable feature flag: `enableApimGatewayPrivateEndpoint = false`
2. Re-deploy (removes conditional resources)
3. Azure will clean up:
   - Application Gateway
   - APIM gateway private endpoint
   - App Gateway subnet
   - APIM PE subnet
   - Private DNS zone for APIM

## References

- Microsoft Learn: [Private endpoints for APIM](https://learn.microsoft.com/en-us/azure/api-management/private-endpoint?tabs=v2)
- Spec: `infra/specs/apim-vnet-integration-spec.md` Section 12.1
- Network topology diagram: Spec Section 12.2
- Traffic flow diagram: Spec Section 12.3

## Cost Impact (when enabled)

- **Application Gateway WAF_v2**: ~$280/month (2 instances base)
- **APIM Gateway Private Endpoint**: ~$10/month
- **Public IP (Standard)**: ~$3.50/month
- **Total estimated increase**: ~$293.50/month

## Security Considerations

1. **WAF Protection**: OWASP 3.2 in Prevention mode blocks common attacks
2. **TLS Termination**: App Gateway handles public TLS, re-encrypts to APIM PE
3. **Network Isolation**: APIM gateway only accessible via PE (if public access disabled)
4. **Certificate Management**: Centralized in Key Vault, auto-rotated
5. **Health Monitoring**: App Gateway probes ensure APIM availability

## Known Limitations

1. **Bicep Conditional Outputs**: Cannot directly output from conditional modules; workaround uses wrapper module
2. **Manual PE Approval**: Private endpoint connection requires manual approval step
3. **DNS Propagation**: May take 5-10 minutes for DNS records to propagate
4. **Certificate Prerequisites**: Key Vault cert must exist before deployment
