param hubName string
param projectName string
param location string
param tags object = {}

// Unique suffixes for supporting resources scoped to this hub
var storageAccountName = 'st${uniqueString(resourceGroup().id, hubName)}'
var keyVaultName = 'kv${uniqueString(resourceGroup().id, hubName)}'
var aiServicesName = 'ais${uniqueString(resourceGroup().id, hubName)}'

// ── Supporting resources ──────────────────────────────────────────────────────

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

// ── Azure AI Services (hosts GPT-4 and Phi-4 deployments) ────────────────────

resource aiServices 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' = {
  name: aiServicesName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: aiServicesName
    publicNetworkAccess: 'Enabled'
  }
}

// Model deployments must be sequential within the same account
// gpt-4o (2024-11-20) with Standard SKU — generally available in westus3
resource gpt4oDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-04-01-preview' = {
  parent: aiServices
  name: 'gpt-4o'
  sku: {
    name: 'Standard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-11-20'
    }
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

// Phi-4-mini-instruct with GlobalStandard SKU — Microsoft format
resource phiDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-04-01-preview' = {
  parent: aiServices
  name: 'Phi-4-mini-instruct'
  dependsOn: [gpt4oDeployment] // deployments in the same account must be sequential
  sku: {
    name: 'GlobalStandard'
    capacity: 1
  }
  properties: {
    model: {
      format: 'Microsoft'
      name: 'Phi-4-mini-instruct'
      version: '1'
    }
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

// ── Azure AI Foundry Hub ──────────────────────────────────────────────────────

resource aiHub 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: hubName
  location: location
  tags: tags
  kind: 'Hub'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    friendlyName: hubName
  }
}

resource aiServicesConnection 'Microsoft.MachineLearningServices/workspaces/connections@2024-04-01' = {
  parent: aiHub
  name: 'aiservices-connection'
  properties: {
    category: 'AIServices'
    target: aiServices.properties.endpoint
    authType: 'AAD' // Managed Identity — no keys stored
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: aiServices.id
    }
  }
}

// ── Azure AI Foundry Project ──────────────────────────────────────────────────

resource aiProject 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: projectName
  location: location
  tags: tags
  kind: 'Project'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hubResourceId: aiHub.id
    friendlyName: projectName
  }
}

// ── RBAC: AI Hub → Key Vault (Secrets Officer) ───────────────────────────────

resource kvSecretsOfficerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, aiHub.id, 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b86a8fe4-44ce-4948-aee5-eccb2c155cd7' // Key Vault Secrets Officer
    )
    principalId: aiHub.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ── RBAC: AI Hub → Storage Account (Storage Blob Data Contributor) ───────────

resource storageBlobDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, aiHub.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
    )
    principalId: aiHub.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ── RBAC: AI Hub → AI Services (Cognitive Services User) ─────────────────────

resource aiServicesUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiServices.id, aiHub.id, 'a97b65f3-24c7-4388-baec-2e87135dc908')
  scope: aiServices
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'a97b65f3-24c7-4388-baec-2e87135dc908' // Cognitive Services User
    )
    principalId: aiHub.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output hubId string = aiHub.id
output projectId string = aiProject.id
output aiServicesEndpoint string = aiServices.properties.endpoint
