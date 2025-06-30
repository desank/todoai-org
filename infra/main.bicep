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

// Generate a unique password based on deployment info
var postgresPassword = '${uniqueString(resourceGroup().id, environmentName)}Pg@${substring(uniqueString(subscription().id), 0, 8)}'

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
          addressPrefix: '10.10.2.0/23'
          // No delegations for ACA subnet
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
      defaultAction: 'Allow' // Allow during deployment
    }
  }
}

// Store the generated password in Key Vault
resource postgresPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name: 'postgres-password'
  properties: {
    value: postgresPassword
  }
}

// Private DNS Zone for PostgreSQL Flexible Server
resource postgresPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.postgres.database.azure.com'
  location: 'global'
  tags: tags
}

// Link VNet to Private DNS Zone
resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${postgresPrivateDnsZone.name}/${environmentName}-vnet-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
  dependsOn: [postgresPrivateDnsZone, vnet]
}

// PostgreSQL Flexible Server
resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: '${environmentName}-pg'
  location: location
  tags: tags
  properties: {
    version: postgresVersion
    administratorLogin: postgresAdminUsername
    administratorLoginPassword: postgresPassword
    storage: {
      storageSizeGB: int(postgresStorageMb / 1024)
    }
    network: {
      delegatedSubnetResourceId: vnet.properties.subnets[0].id
      privateDnsZoneArmResourceId: postgresPrivateDnsZone.id
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
  }
  sku: {
    name: postgresSkuName
    tier: 'Burstable'
    capacity: 1
  }
  dependsOn: [vnet]
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
  tags: union(tags, { 'azd-service-name': 'api' })
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
          name: 'postgres-host'
          value: postgres.properties.fullyQualifiedDomainName
        }
        {
          name: 'postgres-db'
          value: postgresDbName
        }
        {
          name: 'postgres-user'
          value: postgresAdminUsername
        }
        {
          name: 'postgres-password'
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
              secretRef: 'postgres-host'
            }
            {
              name: 'POSTGRES_DB'
              secretRef: 'postgres-db'
            }
            {
              name: 'POSTGRES_USER'
              secretRef: 'postgres-user'
            }
            {
              name: 'POSTGRES_PASSWORD'
              secretRef: 'postgres-password'
            }
          ]
          resources: {
            cpu: '0.5'
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
  dependsOn: [postgresPasswordSecret]
}

// Azure App Service Plan for frontend
resource frontendAppServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: '${environmentName}-frontend-asp'
  location: location
  tags: tags
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
}

// Azure App Service (Web App) for Flutter frontend
resource frontendWebApp 'Microsoft.Web/sites@2022-03-01' = {
  name: '${environmentName}-frontend'
  location: location
  tags: tags
  kind: 'app'
  properties: {
    serverFarmId: frontendAppServicePlan.id
    httpsOnly: true
    siteConfig: {
      appSettings: [
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'true'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
    }
  }
  dependsOn: [frontendAppServicePlan]
}

// Azure Container Registry for container images
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: '${toLower(replace(environmentName, '-', ''))}acr'
  location: location
  tags: union(tags, { 'azd-service-name': 'registry' })
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

output FRONTEND_WEB_APP_URL string = 'https://${frontendWebApp.properties.defaultHostName}'
output API_URL string = apiContainerApp.properties.configuration.ingress.fqdn
