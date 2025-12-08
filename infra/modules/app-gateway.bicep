// https://learn.microsoft.com/azure/templates/microsoft.network/applicationgateways

@description('Location to be used for resources. Defaults to the resource group location')
param location string = resourceGroup().location

@description('The unique suffix to append. Defaults to a unique string based on subscription and resource group IDs.')
param resourceSuffix string = uniqueString(subscription().id, resourceGroup().id)

@description('Application Gateway subnet resource ID.')
param subnetId string

@description('APIM gateway hostname (FQDN) for backend pool configuration.')
param apimGatewayHostname string

@description('Key Vault resource ID containing the TLS certificate.')
param keyVaultId string

@description('Name of the certificate secret in Key Vault.')
param certificateName string = 'appgw-cert'

@description('User-assigned managed identity resource ID with Key Vault Secrets User role.')
param managedIdentityId string

@description('Tags to apply to all resources.')
param tags object = {}

// Get Key Vault URI from resource ID
var keyVaultName = last(split(keyVaultId, '/'))
var keyVaultUri = 'https://${keyVaultName}${environment().suffixes.keyvaultDns}'
var certificateSecretId = '${keyVaultUri}/secrets/${certificateName}'


// ------------------------------
//    RESOURCES
// ------------------------------

// https://learn.microsoft.com/azure/templates/microsoft.network/publicipaddresses
resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-appgw-${resourceSuffix}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: 'appgw-${resourceSuffix}'
    }
  }
}

// https://learn.microsoft.com/azure/templates/microsoft.network/applicationgateways
resource applicationGateway 'Microsoft.Network/applicationGateways@2024-05-01' = {
  name: 'appgw-${resourceSuffix}'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
    }
    autoscaleConfiguration: {
      minCapacity: 2
      maxCapacity: 10
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: subnetId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGatewayFrontendIp'
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port-443'
        properties: {
          port: 443
        }
      }
      {
        name: 'port-80'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'apim-backend-pool'
        properties: {
          backendAddresses: [
            {
              fqdn: apimGatewayHostname
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'apim-https-settings'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          requestTimeout: 30
          probe: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/probes',
              'appgw-${resourceSuffix}',
              'apim-health-probe'
            )
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'https-listener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/frontendIPConfigurations',
              'appgw-${resourceSuffix}',
              'appGatewayFrontendIp'
            )
          }
          frontendPort: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/frontendPorts',
              'appgw-${resourceSuffix}',
              'port-443'
            )
          }
          protocol: 'Https'
          sslCertificate: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/sslCertificates',
              'appgw-${resourceSuffix}',
              certificateName
            )
          }
        }
      }
      {
        name: 'http-listener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/frontendIPConfigurations',
              'appgw-${resourceSuffix}',
              'appGatewayFrontendIp'
            )
          }
          frontendPort: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/frontendPorts',
              'appgw-${resourceSuffix}',
              'port-80'
            )
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'https-routing-rule'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/httpListeners',
              'appgw-${resourceSuffix}',
              'https-listener'
            )
          }
          backendAddressPool: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/backendAddressPools',
              'appgw-${resourceSuffix}',
              'apim-backend-pool'
            )
          }
          backendHttpSettings: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/backendHttpSettingsCollection',
              'appgw-${resourceSuffix}',
              'apim-https-settings'
            )
          }
        }
      }
      {
        name: 'http-redirect-rule'
        properties: {
          ruleType: 'Basic'
          priority: 200
          httpListener: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/httpListeners',
              'appgw-${resourceSuffix}',
              'http-listener'
            )
          }
          redirectConfiguration: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/redirectConfigurations',
              'appgw-${resourceSuffix}',
              'http-to-https-redirect'
            )
          }
        }
      }
    ]
    redirectConfigurations: [
      {
        name: 'http-to-https-redirect'
        properties: {
          redirectType: 'Permanent'
          targetListener: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/httpListeners',
              'appgw-${resourceSuffix}',
              'https-listener'
            )
          }
          includePath: true
          includeQueryString: true
        }
      }
    ]
    probes: [
      {
        name: 'apim-health-probe'
        properties: {
          protocol: 'Https'
          path: '/status-0123456789abcdef'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: false
          host: apimGatewayHostname
          match: {
            statusCodes: [
              '200-399'
            ]
          }
        }
      }
    ]
    sslCertificates: [
      {
        name: certificateName
        properties: {
          keyVaultSecretId: certificateSecretId
        }
      }
    ]
    webApplicationFirewallConfiguration: {
      enabled: true
      firewallMode: 'Prevention'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.2'
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
    }
  }
}


// ------------------------------
//    OUTPUTS
// ------------------------------

@description('Application Gateway resource ID.')
output applicationGatewayId string = applicationGateway.id

@description('Application Gateway name.')
output applicationGatewayName string = applicationGateway.name

@description('Public IP address resource ID.')
output publicIpId string = publicIp.id

@description('Public IP address FQDN.')
output publicIpFqdn string = publicIp.properties.dnsSettings.fqdn

@description('Public IP address.')
output publicIpAddress string = publicIp.properties.ipAddress
