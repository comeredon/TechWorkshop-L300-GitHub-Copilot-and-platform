param hubName string
param projectName string
param location string
param tags object = {}
param logAnalyticsWorkspaceId string

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
    disableLocalAuth: true
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

// ── Diagnostic settings (AI Services → Log Analytics) ──────────────────────

resource aiServicesDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${aiServices.name}'
  scope: aiServices
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
      }
      {
        category: 'RequestResponse'
        enabled: true
      }
      {
        category: 'OpenAIRequestUsage'
        enabled: true
      }
      {
        category: 'Trace'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ── Diagnostic settings (Hub → Log Analytics) ───────────────────────────────

resource aiHubDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${aiHub.name}'
  scope: aiHub
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ── RBAC note ────────────────────────────────────────────────────────────────
// Azure AI Foundry auto-creates and manages all Hub role assignments when the
// workspace is provisioned. The following are created by the platform with
// platform-generated GUIDs and must NOT be declared here — doing so causes a
// RoleAssignmentExists conflict on every deployment:
//   • Key Vault Secrets Officer  (Hub → Key Vault)
//   • Storage Blob Data Contributor (Hub → Storage Account)
//   • Cognitive Services User (Hub → AI Services)
// Only the App Service → AI Services assignment lives in a separate module
// (aifoundry-appservice-rbac.bicep) because it is NOT auto-created.

output hubId string = aiHub.id
output projectId string = aiProject.id
output aiServicesEndpoint string = aiServices.properties.endpoint
output aiServicesName string = aiServices.name
// Azure AI model inference endpoint — used by Azure.AI.Inference SDK to access Phi-4.
// Uses cognitiveservices.azure.com domain so the App Service managed identity's
// "Cognitive Services User" RBAC role (scoped to this AI Services resource) is honoured.
// The services.ai.azure.com alias would require a separate AI Foundry RBAC assignment.
output aiInferenceEndpoint string = 'https://${aiServicesName}.cognitiveservices.azure.com/models'
