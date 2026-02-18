param name string
param location string
param tags object = {}
param appInsightsConnectionString string
param acrLoginServer string
param acrName string
param aiServicesEndpoint string
param aiInferenceEndpoint string

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'asp-${name}'
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  properties: {
    reserved: true // required for Linux
  }
}

resource appService 'Microsoft.Web/sites@2023-12-01' = {
  name: name
  location: location
  tags: union(tags, { 'azd-service-name': 'web' })
  kind: 'app,linux,container'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      // linuxFxVersion is intentionally omitted here — azd deploy manages the
      // container image. Setting it in Bicep would reset it on every provision.
      // Pull from ACR using system-assigned Managed Identity — no passwords
      acrUseManagedIdentityCreds: true
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://${acrLoginServer}'
        }
        {
          name: 'WEBSITES_PORT'
          value: '8080'
        }
        {
          name: 'AZURE_AI_SERVICES_ENDPOINT'
          value: aiServicesEndpoint
        }
        {
          name: 'AZURE_AI_INFERENCE_ENDPOINT'
          value: aiInferenceEndpoint
        }
      ]
    }
  }
}

// Reference the ACR so we can scope the role assignment to it
resource acrResource 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// Grant the App Service Managed Identity the AcrPull role (role ID: 7f951dda-...)
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acrResource.id, appService.id, '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  scope: acrResource
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f951dda-4ed3-4680-a7ca-43fe172d538d'
    )
    principalId: appService.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output id string = appService.id
output name string = appService.name
output uri string = 'https://${appService.properties.defaultHostName}'
output principalId string = appService.identity.principalId
