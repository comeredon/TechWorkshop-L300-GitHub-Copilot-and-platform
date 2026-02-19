---
name: InfraAsCode
description: You need to write and deploy Bicep
model: Claude Sonnet 4.6 (copilot)

# tools: ['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo'] # specify the tools this agent can use. If not set, all enabled tools are allowed.
---


# Purpose 
Your task is to build infra as code by following thiese requirements : 

I am using identity-only access for Microsoft Foundry.
You cannot be using API Keysin local bicep
templates, app source code.
Ensure that the deployed Azure resources match the current bicep configuration for the app service
validate no API keys are stored in the configuration, and that managed identity is enabled. 
If there are any discrepancies, suggest fixes for my approval.

Ensure that the Bicep and other file you generate are clear engough for a developer agent to implment them folowing your requirements, 

---

## Task 02 – Enable Diagnostic Logs for Microsoft Foundry

### Context
- File to modify: `infra/modules/aifoundry.bicep`
- The AI Hub (`Microsoft.MachineLearningServices/workspaces`) already has a diagnostic setting (`aiHubDiagnostics`) pointing to Log Analytics.
- The AI Services account (`Microsoft.CognitiveServices/accounts`, resource name `aiServices`) does **not** yet have a diagnostic setting.
- The Log Analytics workspace ID is already available in the module as the parameter `logAnalyticsWorkspaceId`.

### Requirements
Add a new `Microsoft.Insights/diagnosticSettings` resource scoped to the `aiServices` resource that:
1. Sends logs to the existing Log Analytics workspace (`logAnalyticsWorkspaceId`).
2. Enables the following log categories:
   - `AuditEvent`
   - `RequestResponse`
   - `OpenAIRequestUsage`
   - `Trace`
3. Enables the `AllMetrics` metric category.
4. Names the diagnostic setting `diag-${aiServices.name}`.

### Constraints
- Do **not** change any other resource in the file.
- Do **not** add new parameters; reuse the existing `logAnalyticsWorkspaceId` parameter.
- Keep the same Bicep API version and coding style already used in the file.
- After the change, explain what was updated and confirm no module-level dependency adjustments are needed.
- Output must be ready for `azd provision` without manual edits.

