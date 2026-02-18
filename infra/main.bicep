targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@description('Primary location for all resources')
param location string = 'westus3'

@description('Name of the existing resource group to deploy into')
param resourceGroupName string = 'GHC300trainingCRE'

var resourceToken = toLower(uniqueString(subscription().id, resourceGroupName, location))
var tags = { 'azd-env-name': environmentName }

// Reference the existing resource group instead of creating a new one
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: resourceGroupName
}

module logAnalytics './modules/loganalytics.bicep' = {
  name: 'loganalytics'
  scope: rg
  params: {
    name: 'law-${resourceToken}'
    location: location
    tags: tags
  }
}

module appInsights './modules/appinsights.bicep' = {
  name: 'appinsights'
  scope: rg
  params: {
    name: 'appi-${resourceToken}'
    location: location
    tags: tags
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
  }
}

module acr './modules/acr.bicep' = {
  name: 'acr'
  scope: rg
  params: {
    name: 'cr${resourceToken}'
    location: location
    tags: tags
  }
}

module appService './modules/appservice.bicep' = {
  name: 'appservice'
  scope: rg
  params: {
    name: 'app-${resourceToken}'
    location: location
    tags: tags
    appInsightsConnectionString: appInsights.outputs.connectionString
    acrLoginServer: acr.outputs.loginServer
    acrName: acr.outputs.name
  }
}

module aiFoundry './modules/aifoundry.bicep' = {
  name: 'aifoundry'
  scope: rg
  params: {
    hubName: 'aih-${resourceToken}'
    projectName: 'aip-${resourceToken}'
    location: location
    tags: tags
  }
}

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP string = resourceGroupName
output SERVICE_WEB_NAME string = appService.outputs.name
output SERVICE_WEB_URI string = appService.outputs.uri
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.outputs.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = acr.outputs.name
output APPLICATIONINSIGHTS_CONNECTION_STRING string = appInsights.outputs.connectionString
output AZURE_AI_SERVICES_ENDPOINT string = aiFoundry.outputs.aiServicesEndpoint
