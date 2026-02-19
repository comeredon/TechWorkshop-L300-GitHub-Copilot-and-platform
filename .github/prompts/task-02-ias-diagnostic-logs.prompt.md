---
mode: agent
agent: InfraAsCode
description: Task 02 – Enable diagnostic logs for Microsoft Foundry (IaS prompt)
---

# Task 02 – Enable Diagnostic Logs for Microsoft Foundry

## Constraint
> **Do NOT modify any file under `.github/agents/`.** Agent definitions are managed separately and must not be altered by this prompt.

## Context
- File to modify: `infra/modules/aifoundry.bicep`
- The AI Hub (`Microsoft.MachineLearningServices/workspaces`) already has a diagnostic setting (`aiHubDiagnostics`) pointing to Log Analytics.
- The AI Services account (`Microsoft.CognitiveServices/accounts`, resource name `aiServices`) does **not** yet have a diagnostic setting.
- The Log Analytics workspace ID is already available in the module as the parameter `logAnalyticsWorkspaceId`.

## Requirements
Add a new `Microsoft.Insights/diagnosticSettings` resource scoped to the `aiServices` resource that:
1. Sends logs to the existing Log Analytics workspace (`logAnalyticsWorkspaceId`).
2. Enables the following log categories:
   - `AuditEvent`
   - `RequestResponse`
   - `OpenAIRequestUsage`
   - `Trace`
3. Enables the `AllMetrics` metric category.
4. Names the diagnostic setting `diag-${aiServices.name}`.

## Constraints
- Do **not** change any other resource in the file.
- Do **not** add new parameters; reuse the existing `logAnalyticsWorkspaceId` parameter.
- Keep the same Bicep API version and coding style already used in the file.
- After the change, explain what was updated and confirm no module-level dependency adjustments are needed.
- Output must be ready for `azd provision` without manual edits.
