// Grants the App Service system-assigned managed identity the
// "Cognitive Services User" role on the AI Services accounts.
// Lives in a separate module to break the circular dependency between
// appservice.bicep (needs aiServicesEndpoint) and aifoundry.bicep
// (needs appServicePrincipalId).

param aiServicesName string
param aiImageServicesName string
param appServicePrincipalId string

resource aiServices 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' existing = {
  name: aiServicesName
}

resource imageServices 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' existing = {
  name: aiImageServicesName
}

resource cognitiveServicesUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiServices.id, appServicePrincipalId, 'a97b65f3-24c7-4388-baec-2e87135dc908')
  scope: aiServices
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'a97b65f3-24c7-4388-baec-2e87135dc908' // Cognitive Services User
    )
    principalId: appServicePrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource imageServicesUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(imageServices.id, appServicePrincipalId, 'a97b65f3-24c7-4388-baec-2e87135dc908')
  scope: imageServices
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'a97b65f3-24c7-4388-baec-2e87135dc908' // Cognitive Services User
    )
    principalId: appServicePrincipalId
    principalType: 'ServicePrincipal'
  }
}
