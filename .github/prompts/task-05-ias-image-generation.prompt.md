---
mode: agent
agent: InfraAsCode
description: Task 05 – Deploy DALL-E 3 image generation model (IaS prompt)
---

# Task 05 – Deploy DALL-E 3 Image Generation Model

## Constraint
> **Do NOT modify any file under `.github/agents/`.** Agent definitions are managed separately and must not be altered by this prompt.

## Context
- Infrastructure root: `infra/`
- Entry point: `infra/main.bicep`
- AI model deployments live in `infra/modules/aifoundry.bicep`
- Existing deployments (all in the same `aiServices` account):
  - `gpt-4o` (OpenAI format, Standard SKU, capacity 10)
  - `Phi-4-mini-instruct` (Microsoft format, GlobalStandard SKU, capacity 1) — depends on `gpt-4o`
- All deployments in the same AI Services account **must be sequential** — each must `dependsOn` the previous one.
- The App Service already receives `AZURE_AI_SERVICES_ENDPOINT` as an app setting (defined in `infra/modules/appservice.bicep`).
- The App Service managed identity already holds the `Cognitive Services User` role on the AI Services account (via `infra/modules/aifoundry-appservice-rbac.bicep`). **This role grants access to DALL-E 3 as well — no new RBAC is needed.**

Read `infra/modules/aifoundry.bicep`, `infra/modules/appservice.bicep`, and `infra/main.bicep` before making any changes.

## Requirements

### 1. Add DALL-E 3 Deployment to `infra/modules/aifoundry.bicep`

After the existing `phiDeployment` resource block, add a new deployment resource:

```bicep
// DALL-E 3 — image generation model with OpenAI format
resource dalleDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-04-01-preview' = {
  parent: aiServices
  name: 'dall-e-3'
  dependsOn: [phiDeployment] // deployments in the same account must be sequential
  sku: {
    name: 'Standard'
    capacity: 1
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'dall-e-3'
      version: '3.0'
    }
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}
```

> **Region note:** DALL-E 3 with Standard SKU is available in `westus3`. If deployment fails with `ModelNotAvailable`, verify region availability in the [Azure OpenAI model availability documentation](https://learn.microsoft.com/en-us/azure/ai-services/openai/concepts/models).

After the existing outputs in `infra/modules/aifoundry.bicep`, add:

```bicep
output aiImageDeploymentName string = dalleDeployment.name
```

---

### 2. Add Parameter to `infra/modules/appservice.bicep`

Add a new parameter at the top of the parameters section:

```bicep
param aiImageDeploymentName string
```

Inside the `appService` resource, in the `appSettings` array, add a new entry after the existing `AZURE_AI_INFERENCE_ENDPOINT` setting:

```bicep
{
  name: 'AZURE_AI_IMAGE_DEPLOYMENT_NAME'
  value: aiImageDeploymentName
}
```

---

### 3. Update `infra/main.bicep`

In the `appService` module block, add the new parameter after the existing `aiInferenceEndpoint` line:

```bicep
aiImageDeploymentName: aiFoundry.outputs.aiImageDeploymentName
```

Do not change any other part of `main.bicep`.

---

## Constraints
- Do **not** modify `infra/modules/aifoundry-appservice-rbac.bicep` — the existing `Cognitive Services User` role already covers DALL-E 3.
- Do **not** modify any other existing module files (loganalytics, appinsights, acr, workbook).
- Do **not** add new parameters to `main.bicepparam`.
- Do **not** modify any file under `.github/agents/`.
- Keep changes minimal: only `infra/modules/aifoundry.bicep` (new deployment + output), `infra/modules/appservice.bicep` (new param + app setting), and `infra/main.bicep` (one new wire param).

## Validation
After implementing, run the following command and confirm it exits without errors:
```bash
az bicep build --file infra/main.bicep
```
Report which files were created or modified and confirm no other files were touched.
