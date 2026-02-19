---
mode: agent
agent: InfraAsCode
description: Task 04 – Deploy an Azure Monitor Workbook for AI Services observability (IaS prompt)
---

# Task 04 – Deploy an AI Services Observability Workbook

## Constraint
> **Do NOT modify any file under `.github/agents/`.** Agent definitions are managed separately and must not be altered by this prompt.

## Context
- Infrastructure root: `infra/`
- Entry point: `infra/main.bicep`
- Existing modules: `infra/modules/` (loganalytics.bicep, appinsights.bicep, aifoundry.bicep, appservice.bicep, acr.bicep, aifoundry-appservice-rbac.bicep)
- The `logAnalytics` module in `main.bicep` already outputs its resource ID as `logAnalytics.outputs.id`.
- The existing resource group is referenced as `rg` with `resourceToken` used for unique resource naming.

Read `infra/main.bicep` and `infra/modules/loganalytics.bicep` before making any changes.

## Requirements

### 1. Create `infra/modules/workbook.bicep`

Create a new Bicep module file with the following:

**Parameters:**
```bicep
param name string
param location string
param tags object
param workspaceResourceId string
```

**Resource:** Deploy `microsoft.insights/workbooks@2022-04-01` with:
- `kind: 'shared'`
- `category: 'workbook'`
- `displayName: 'AI Services Observability'`
- `sourceId: workspaceResourceId`
- `serializedData`: the workbook JSON below, embedded as an **inline Bicep string**. Use string interpolation to substitute the `workspaceResourceId` parameter into the `fallbackResourceIds` array — do NOT create a separate JSON file.

**Workbook JSON to embed inline:**
```json
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 1,
      "content": {
        "json": "## AI Services Observability\nThis workbook visualizes Azure AI Services operational data using platform diagnostics from the AzureDiagnostics table.\n\nIt includes:\n- Request volume over time\n- Latency percentiles (p50/p95/p99)\n- Breakdown by operation name"
      },
      "name": "text - 0"
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "AzureDiagnostics\n| where ResourceProvider == \"MICROSOFT.COGNITIVESERVICES\"\n| where Category == \"RequestResponse\"\n| summarize Requests = count() by bin(TimeGenerated, 5m)\n| order by TimeGenerated asc",
        "size": 1,
        "title": "Request Volume Over Time",
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces",
        "visualization": "timechart",
        "chartSettings": {
          "yAxis": ["Requests"]
        }
      },
      "name": "RequestVolume"
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "AzureDiagnostics\n| where ResourceProvider == \"MICROSOFT.COGNITIVESERVICES\"\n| where Category == \"RequestResponse\"\n| summarize\n p50 = percentiles(DurationMs, 50),\n p95 = percentiles(DurationMs, 95),\n p99 = percentiles(DurationMs, 99)\n by bin(TimeGenerated, 5m)\n| order by TimeGenerated asc",
        "size": 1,
        "title": "Latency Percentiles (p50 / p95 / p99)",
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces",
        "visualization": "timechart"
      },
      "name": "LatencyTrends"
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "AzureDiagnostics\n| where ResourceProvider == \"MICROSOFT.COGNITIVESERVICES\"\n| where Category == \"RequestResponse\"\n| extend Operation = OperationName\n| summarize Count = count() by bin(TimeGenerated, 5m), Operation\n| order by TimeGenerated asc",
        "size": 1,
        "title": "Requests by Operation Name Over Time",
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces",
        "visualization": "timechart",
        "chartSettings": {
          "yAxis": ["Count"]
        }
      },
      "name": "OperationBreakdown"
    }
  ],
  "fallbackResourceIds": ["<WORKSPACE_RESOURCE_ID>"]
}
```

Replace `<WORKSPACE_RESOURCE_ID>` with the `workspaceResourceId` parameter using Bicep string interpolation when constructing the `serializedData` string.

---

### 2. Update `infra/main.bicep`

Add the following module block after the existing `logAnalytics` module block. Do not change any other part of `main.bicep`:

```bicep
module workbook './modules/workbook.bicep' = {
  name: 'workbook'
  scope: rg
  params: {
    name: 'workbook-${resourceToken}'
    location: location
    tags: tags
    workspaceResourceId: logAnalytics.outputs.id
  }
}
```

---

## Constraints
- Do **not** create a separate `workbook.json` file — the JSON is embedded inline in the Bicep module.
- Do **not** modify any other existing module files.
- Do **not** add new parameters to `main.bicepparam`.
- Do **not** modify any file under `.github/agents/`.
- Keep all changes minimal: only `infra/modules/workbook.bicep` (new) and `infra/main.bicep` (one new module block).

## Validation
After implementing the changes, run the following command and confirm it exits without errors:
```bash
az bicep build --file infra/main.bicep
```
Report which files were created or modified and confirm no other files were touched.
