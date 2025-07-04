param environmentName string = 'famtodo-${uniqueString(resourceGroup().id)}'
param location string = resourceGroup().location
param tags object = {
  Application: 'todoai-org'
}

// Cosmos DB parameters
param cosmosDbAccountName string = '${environmentName}-cosmos'
param cosmosDbName string = 'familytodo-db'
param cosmosContainerName string = 'family_groups'

// VNet for the app (still useful for Container Apps)
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
        name: 'appsSubnet'
        properties: {
          addressPrefix: '10.10.2.0/23'
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
      defaultAction: 'Allow'
    }
  }
}

// Azure Cosmos DB account
resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: cosmosDbAccountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    // VNet integration for Cosmos DB is more complex and can be added later if needed.
    // For now, we'll use key-based auth from the container app.
    publicNetworkAccess: 'Enabled'
  }
}

// Cosmos DB for NoSQL Database
resource cosmosDb 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  parent: cosmosDbAccount
  name: cosmosDbName
  properties: {
    resource: {
      id: cosmosDbName
    }
  }
}

// Cosmos DB Container
resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: cosmosDb
  name: cosmosContainerName
  properties: {
    resource: {
      id: cosmosContainerName
      partitionKey: {
        paths: [
          '/id' // Partitioning by family ID is a good starting point
        ]
        kind: 'Hash'
      }
    }
    options: {
      throughput: 400
    }
  }
}

// Store the Cosmos DB Primary Key in Key Vault
resource cosmosDbPrimaryKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name: 'cosmos-primary-key'
  properties: {
    value: cosmosDbAccount.listKeys().primaryMasterKey
  }
}

// Managed Environment for Container Apps
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: '${environmentName}-env'
  location: location
  tags: tags
  properties: {
    vnetConfiguration: {
      internal: false // Keep it simple for now
      infrastructureSubnetId: vnet.properties.subnets[0].id
    }
  }
}

// API Container App
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
          name: 'cosmos-endpoint'
          value: cosmosDbAccount.properties.documentEndpoint
        }
        {
          name: 'cosmos-key'
          value: '@Microsoft.KeyVault(SecretUri=${keyVault.properties.vaultUri}secrets/cosmos-primary-key)'
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
              name: 'COSMOS_ENDPOINT'
              secretRef: 'cosmos-endpoint'
            }
            {
              name: 'COSMOS_KEY'
              secretRef: 'cosmos-key'
            }
            {
              name: 'COSMOS_DATABASE_NAME'
              value: cosmosDbName
            }
            {
              name: 'COSMOS_CONTAINER_NAME'
              value: cosmosContainerName
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
  dependsOn: [cosmosDbPrimaryKeySecret]
}

// Azure Static Web App for the frontend
resource frontendStaticWebApp 'Microsoft.Web/staticSites@2022-09-01' = {
  name: '${environmentName}-frontend'
  location: location
  tags: union(tags, { 'azd-service-name': 'web' })
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    // Configuration for the SWA will be handled by azd
  }
}

// Outputs for azd
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = subscription().tenantId
output AZURE_KEY_VAULT_NAME string = keyVault.name
output COSMOS_DB_ACCOUNT_NAME string = cosmosDbAccount.name
output COSMOS_DB_NAME string = cosmosDb.name
output COSMOS_CONTAINER_NAME string = cosmosContainer.name
output API_URL string = apiContainerApp.properties.configuration.ingress.fqdn
output FRONTEND_URL string = 'https://${frontendStaticWebApp.properties.defaultHostname}'