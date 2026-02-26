# Use-Case Onboarding Guide

> **Applies to branches**: `jwtauth` · `usecaseonboard`

This gateway implements the **AI Access Contract** principle from the [Foundry Citadel Platform](https://github.com/azure-samples/ai-hub-gateway-solution-accelerator/tree/citadel-v1) — an enterprise-grade layered AI security architecture. An *AI Access Contract* is a version-controlled, declarative declaration of the governed AI resources a use case needs (LLMs, quotas, policies), deployed as infrastructure-as-code alongside precise governance guardrails.

The two branches add three capabilities on top of the base gateway:

| Capability | Branch | What it does |
|---|---|---|
| Entra ID JWT auth | `jwtauth` | Validates every request against an app registration; enforces per-deployment access via app roles |
| Subscription key enforcement | `usecaseonboard` | Requires an APIM product subscription key on every call |
| Citadel Access Contracts | `usecaseonboard` | Automates APIM product/subscription creation and Key Vault secrets per use case; Foundry connections are scaffolded but **not yet implemented** (TODO) |

---

1. [Part 1 — JWT Auth Setup](#part-1--jwt-auth-setup-jwtauth)
2. [Part 2 — Use-Case Contract Deployment](#part-2--use-case-contract-deployment-usecaseonboard)
3. [Testing](#testing)
4. [Setup Checklist](#setup-checklist)

---

## Part 1 — JWT Auth Setup (`jwtauth`)

### How it works

Every inbound request goes through this policy sequence:

```
Request arrives at APIM
  1. Extract deployment name (from URL path for Azure OAI / from body for v1)
  2. validate-azure-ad-token  →  verify signature, audience, tenant
  3. Check roles claim contains deployment name  →  403 if missing
  4. Resolve caller identity (UPN or Graph lookup, cached 8 h)
  5. authentication-managed-identity  →  forward to Azure OpenAI
  6. Emit token metrics with Caller dimension
```

APIM validates the JWT against your app registration, then uses its own managed identity to call Azure OpenAI — callers never need a Cognitive Services credential.

### Step 1 — Register an Entra ID app

1. **Azure Portal → Entra ID → App registrations → New registration**
   - Name: `apim-ai-gateway` (or similar), Single tenant, no redirect URI
   - Note the **Application (client) ID**
2. **Expose an API** → set Application ID URI to `api://<client-id>`
3. **Add a scope**: name `access_as_user`, admin + user consent, Enabled
4. **Authorized client applications** → add `04b07795-8ddb-461a-bbee-02f9e1bf7b46` *(Azure CLI, for local dev)*

### Step 2 — Create app roles (one per deployment)

**App roles → Create app role** for each deployment name in your parameters file:

| Field | Value |
|-------|-------|
| Allowed member types | Both (Users/Groups + Applications) |
| Value | e.g. `gpt-5-mini` — **must exactly match the deployment name** |

### Step 3 — Assign roles

- **Users/groups**: Entra ID → Enterprise Applications → your app → Users and groups → Add
- **Service principals**: Client app → API permissions → My APIs → your app → Application permissions → Grant admin consent

### Step 4 — Add named values to APIM

In `infra/main.bicep`, inside the `apimConfig` module `namedValues` array:

```bicep
{ name: 'aad-tenant',    value: '<your-tenant-id>' }
{ name: 'apim-audience', value: 'api://<your-app-client-id>' }
```

Redeploy the gateway after making this change.

### Optional — caller display name in metrics

Grant `ServicePrincipal.Read.All` to the managed identity so the policy can resolve SPN display names in Application Insights:

```powershell
$body = @{
    principalId = "<managed-identity-principal-id>"  # deployment output
    resourceId  = $(az ad sp show --id 00000003-0000-0000-c000-000000000000 --query id -o tsv)
    appRoleId   = "9a5d68dd-52b0-4cc2-bd40-abcf44ac3a30"  # ServicePrincipal.Read.All
} | ConvertTo-Json
$body | Out-File "$env:TEMP\body.json" -Encoding utf8 -NoNewline
az rest --method POST `
  --url "https://graph.microsoft.com/v1.0/servicePrincipals/<managed-identity-principal-id>/appRoleAssignments" `
  --headers "Content-Type=application/json" --body "@$env:TEMP\body.json"
```

> **Token revocation**: Tokens are cached up to 1 hour. To force re-auth during testing run `az logout && az login --tenant <tenant-id>`.

---

## Part 2 — Use-Case Contract Deployment (`usecaseonboard`)

### What changed in the gateway

Both APIs now require a product subscription key (`infra/modules/apim.bicep`):

| Setting | Before | After |
|---------|--------|-------|
| `subscriptionRequired` | `false` | `true` |
| Key header | `api-key` | `Ocp-Apim-Subscription-Key` |
| Key query param | `api-key` | `subscription-key` |

### Citadel Access Contracts

The `infra/citadel-access-contracts/` module is this repository's implementation of the [AI Access Contract](https://github.com/azure-samples/ai-hub-gateway-solution-accelerator/tree/citadel-v1#-ai-citadel-contracts---connect-agents-to-governance-hub) principle from the Foundry Citadel Platform. Each contract is a version-controlled `.bicepparam` file that declares:

- Which AI services the use case needs (LLMs, Document Intelligence, Search, …)
- Governance policies (token quotas scoped to `subscriptionId + deploymentName`, content safety, etc.)
- Where credentials are stored (Key Vault) or surfaced (deployment output / Foundry connection)

One deployment creates:

| Resource | Naming Pattern |
|----------|---------------|
| APIM Product | `<serviceCode>-<BU>-<UseCase>-<ENV>` |
| APIM Subscription | `<product>-SUB-01` |
| Key Vault Secrets *(optional)* | configurable names |
| Foundry Connection | `<prefix>-<serviceCode>` — ⚠️ **TODO: not yet implemented** (`useTargetFoundry = false`) |

> **Foundry integration (TODO)**: The `foundry` and `foundryConfig` parameters and the `foundryConnection.bicep` module are scaffolded but the end-to-end Foundry connection flow has not been tested or completed. Set `useTargetFoundry = false` until this is implemented.

See [infra/citadel-access-contracts/README.md](../infra/citadel-access-contracts/README.md) for the full parameter reference and advanced scenarios.

### Step 1 — Create a contract

```powershell
# Folder pattern: contracts/<bu-usecase>/<env>/
$path = "infra/citadel-access-contracts/contracts/hr-chatagent/dev"
New-Item -ItemType Directory -Force -Path $path
Copy-Item infra/citadel-access-contracts/main.bicepparam "$path/main.bicepparam"
Copy-Item infra/citadel-access-contracts/policies/default-ai-product-policy.xml "$path/ai-product-policy.xml"
```

Edit `main.bicepparam` — minimum changes:

```bicep
using '../../../main.bicep'

param apim         = { subscriptionId: '...', resourceGroupName: '...', name: '...' }
param keyVault     = { subscriptionId: '...', resourceGroupName: '...', name: '...' }
param useTargetAzureKeyVault = true   // false → output credentials directly

param useCase = { businessUnit: 'HR', useCaseName: 'ChatAgent', environment: 'DEV' }

param apiNameMapping = { LLM: ['azure-openai-api', 'universal-llm-api'] }

param services = [
  {
    code: 'LLM'
    endpointSecretName: 'HR-CHATAGENT-LLM-ENDPOINT'
    apiKeySecretName:   'HR-CHATAGENT-LLM-KEY'
    policyXml: loadTextContent('ai-product-policy.xml')   // '' = use default
  }
]
```

### Step 2 — Deploy

```powershell
# Preview
az deployment sub what-if `
  --location westeurope `
  --template-file infra/citadel-access-contracts/main.bicep `
  --parameters infra/citadel-access-contracts/contracts/hr-chatagent/dev/main.bicepparam

# Deploy
az deployment sub create `
  --name hr-chatagent-dev --location westeurope `
  --template-file infra/citadel-access-contracts/main.bicep `
  --parameters infra/citadel-access-contracts/contracts/hr-chatagent/dev/main.bicepparam
```

### Step 3 — Retrieve the subscription key

```powershell
# From Key Vault (useTargetAzureKeyVault = true)
$key = az keyvault secret show --vault-name <kv-name> --name hr-chatagent-llm-key --query value -o tsv

# From deployment output (useTargetAzureKeyVault = false)
$output = az deployment sub show --name hr-chatagent-dev `
           --query properties.outputs.endpoints.value -o json | ConvertFrom-Json
$key = ($output | Where-Object { $_.code -eq 'LLM' }).apiKey
```

---

## Testing

Set two environment variables before running any test:

```powershell
$env:APIM_ENDPOINT         = "https://<your-apim>.azure-api.net"
$env:APIM_SUBSCRIPTION_KEY = "<key from Key Vault or deployment output>"
az login --tenant "<your-tenant-id>"
```

The test client sends **both** a JWT and a subscription key:

```python
token_provider = get_bearer_token_provider(
    DefaultAzureCredential(),
    "api://<your-app-client-id>/.default"  # audience = app registration, NOT Cognitive Services
)
client = AzureOpenAI(
    azure_endpoint=APIM_ENDPOINT,
    api_version="2024-12-01-preview",
    azure_ad_token_provider=token_provider,
    default_headers={"Ocp-Apim-Subscription-Key": APIM_SUBSCRIPTION_KEY}
)
```

```powershell
cd tests
python test_azure_openai.py
python test_openai_v1.py
python test_models_v1.py
```

---

## Setup Checklist

**Gateway (one-time)**
- [ ] Deploy core gateway — `.\deploy.ps1`
- [ ] Register Entra ID app, set App ID URI, add `access_as_user` scope, authorise Azure CLI client
- [ ] Add `aad-tenant` and `apim-audience` named values in `infra/main.bicep` → redeploy
- [ ] Create one app role per deployment name; assign to users / service principals
- [ ] *(Optional)* Grant `ServicePrincipal.Read.All` to managed identity for SPN display names

**Per use case**
- [ ] Create contract folder — `contracts/<bu-usecase>/<env>/`
- [ ] Configure `main.bicepparam` with APIM, Key Vault, use-case, and services
- [ ] Deploy — `az deployment sub create ...`
- [ ] Retrieve subscription key from Key Vault or deployment output
- [ ] Set `APIM_SUBSCRIPTION_KEY` env var and run tests
