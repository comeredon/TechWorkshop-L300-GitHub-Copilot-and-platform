---
mode: agent
agent: developer
description: Task 02 – Verify diagnostic log flow for Microsoft Foundry (developer prompt)
---

# Task 02 – Verify Diagnostic Log Flow for Microsoft Foundry

## Constraint
> **Do NOT modify any file under `.github/agents/`.** Agent definitions are managed separately and must not be altered by this prompt.

## Context
The InfraAsCode agent has updated `infra/modules/aifoundry.bicep` to add a diagnostic setting on the Azure AI Services account. After `azd provision` has been run, your role is to verify that logs are flowing correctly into Log Analytics.

## Requirements
1. Use the chat feature of the deployed web application for a few minutes to generate AI request activity.
2. Run the following Log Analytics query and confirm recent entries appear for the AI Services resource:

```kusto
AzureDiagnostics
| where ResourceProvider =~ "MICROSOFT.COGNITIVESERVICES"
| sort by TimeGenerated desc
```

3. Confirm the following log categories are present in the query results:
   - `AuditEvent`
   - `RequestResponse`
   - `OpenAIRequestUsage`
   - `Trace`

## Constraints
- Do **not** modify any application source code for this task — it is a pure infrastructure verification.
- Do **not** modify any file under `.github/agents/` — agent definitions are out of scope.
- If logs do not appear within 10 minutes, re-run the query before concluding there is an issue (diagnostic logs can take 2–10 minutes to appear).
- Report the query results back for approval before marking the task complete.
