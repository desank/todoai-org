param environmentName string = 'famtodo-${uniqueString(resourceGroup().id)}'
param location string = resourceGroup().location
param tags object = {
  Application: 'todoai-org'
}
param postgresAdminUsername string = 'pgadmin'
param postgresDbName string = 'familytodo'
param postgresSkuName string = 'Standard_B1ms'
param postgresVersion string = '16'
param postgresStorageMb int = 32768

// VNet for the app
resource vnet 'Microsoft.Network/virtualNetworks@2023-02-01' = {
  name: '${environmentName}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.10.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'postgresSubnet'
        properties: {
          addressPrefix: '10.10.1.0/24'
          delegations: [
            {
              name: 'fsDelegation'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
        }
      }
      {
        name: 'appsSubnet'
        properties: {
          addressPrefix: '10.10.2.0/24'
          delegations: [
            {
              name: 'acaDelegation'
              properties: {
                serviceName: 'Microsoft.App/managedEnvironments'
              }
            }
          ]
        }
      }
    ]
  }
}

// Key Vault for secrets
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: '${environmentName}-kv'
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    accessPolicies: [] // Will be managed by azd/managed identity
    enableSoftDelete: true
    enablePurgeProtection: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
  }
}

// PostgreSQL Flexible Server
resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2023-11-01' = {
  name: '${environmentName}-pg'
  location: location
  tags: tags
  properties: {
    version: postgresVersion
    administratorLogin: postgresAdminUsername
    administratorLoginPassword: listSecret('${keyVault.id}/secrets/postgres-password', '2023-02-01').value
    storage: {
      storageSizeGB: int(postgresStorageMb / 1024)
    }
    network: {
      delegatedSubnetResourceId: vnet.properties.subnets[0].id
    }
    highAvailability: {
      mode: 'Disabled'
    }
    createMode: 'Default'
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    authentication: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
    dataEncryption: {
      type: 'AzureKeyVault'
    }
  }
  sku: {
    name: postgresSkuName
    tier: 'Burstable'
    capacity: 1
  }
  dependsOn: [keyVault, vnet]
}

// Managed Environment for Container Apps (in appsSubnet)
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: '${environmentName}-env'
  location: location
  tags: tags
  properties: {
    daprAIInstrumentationKey: applicationInsights.properties.InstrumentationKey
    vnetConfiguration: {
      infrastructureSubnetId: vnet.properties.subnets[1].id
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${environmentName}-ai'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

// API Container App (connects to PostgreSQL via VNet, gets password from Key Vault)
resource apiContainerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: '${environmentName}-api'
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8000
        transport: 'auto'
      }
      secrets: [
        {
          name: 'POSTGRES_HOST'
          value: postgres.properties.fullyQualifiedDomainName
        }
        {
          name: 'POSTGRES_DB'
          value: postgresDbName
        }
        {
          name: 'POSTGRES_USER'
          value: postgresAdminUsername
        }
        {
          name: 'POSTGRES_PASSWORD'
          value: '@Microsoft.KeyVault(SecretUri=${keyVault.properties.vaultUri}secrets/postgres-password)'
        }
      ]
    }
    template: {
      containers: [
        {
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest' // Placeholder, azd will replace
          name: 'api'
          env: [
            {
              name: 'POSTGRES_HOST'
              secretRef: 'POSTGRES_HOST'
            }
            {
              name: 'POSTGRES_DB'
              secretRef: 'POSTGRES_DB'
            }
            {
              name: 'POSTGRES_USER'
              secretRef: 'POSTGRES_USER'
            }
            {
              name: 'POSTGRES_PASSWORD'
              secretRef: 'POSTGRES_PASSWORD'
            }
          ]
          resources: {
            cpu: 0.5
            memory: '1.0Gi'
          }
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 1
      }
    }
  }
}

resource staticWebApp 'Microsoft.Web/staticSites@2022-03-01' = {
  name: '${environmentName}-web'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {}
}

output STATIC_WEB_APP_URL string = staticWebApp.properties.defaultHostname
output API_URL string = apiContainerApp.properties.configuration.ingress.fqdn
