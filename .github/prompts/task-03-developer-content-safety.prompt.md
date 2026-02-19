---
mode: agent
agent: developer
description: Task 03 – Enforce content safety for user prompts (developer prompt)
---

# Task 03 – Enforce Content Safety for User Prompts

## Constraint
> **Do NOT modify any file under `.github/agents/`.** Agent definitions are managed separately and must not be altered by this prompt.

## Context
- App: ASP.NET Core (.NET 10), located in `src/`
- File to modify: `src/Services/ChatService.cs`
- Project file: `src/ZavaStorefront.csproj`
- The app already uses `Azure.Identity` and `DefaultAzureCredential` (via a `CognitiveServicesCredential` wrapper) — no API keys anywhere.
- The AI Services endpoint is available via `config["AZURE_AI_SERVICES_ENDPOINT"]` — reuse this same key for the Content Safety client; do NOT add a new config key.
- `ILogger<ChatService>` must be injected and used for logging.

## Requirements

### 1. Add NuGet Package
Add the following package to `src/ZavaStorefront.csproj`:
```xml
<PackageReference Include="Azure.AI.ContentSafety" Version="1.0.0" />
```

### 2. Add Content Safety Client
In `ChatService`, add a `ContentSafetyClient` field. Initialize it in the constructor using:
- The same `AZURE_AI_SERVICES_ENDPOINT` config value already used for the inference client.
- The same `CognitiveServicesCredential` (already defined in the class) — no API keys.

### 3. Inject ILogger
Add `ILogger<ChatService>` as a constructor parameter and store it as a private field.

### 4. Add `CheckContentSafetyAsync` Helper Method
Add a private async method with this signature:
```csharp
private async Task<(bool isSafe, string? blockedReason)> CheckContentSafetyAsync(string text)
```

The method must:
1. Call `AnalyzeTextAsync` on the Content Safety client with the user's text.
2. Check all four standard categories: `Violence`, `Sexual`, `SelfHarm`, `Hate`.
3. Treat severity **>= 2** as unsafe (hardcoded — do not read from config).
4. Log the full result on **every call** using `ILogger` with the following format:
   - One log line per category (Information level):
     ```
     ContentSafety: category={Category} severity={Severity}
     ```
   - One summary line (Information level):
     ```
     ContentSafety: result=PASS prompt_length={length}
     ```
     or, if blocked:
     ```
     ContentSafety: result=BLOCKED category={Category} severity={Severity}
     ```
5. Return `(true, null)` if all categories are below threshold, or `(false, "<CategoryName>")` for the first category that exceeds the threshold.

### 5. Wrap Existing Inference Call in `GetResponseAsync`
At the top of `GetResponseAsync`, **before** the existing relevance guard (`IsRelatedToStore`), call `CheckContentSafetyAsync`. If the result is unsafe, immediately return:
```
"I'm sorry, I can't help with that. Your message was flagged for safety concerns."
```
If safe, continue with the existing logic unchanged.

## Constraints
- Do **not** refactor, rename, or restructure any existing code.
- Do **not** add any new config keys or environment variables.
- Do **not** use API keys — use the `CognitiveServicesCredential` already defined in the class.
- Do **not** catch and swallow Content Safety exceptions — let them propagate so App Service logs surface the error.
- Keep all changes minimal and contained to `ChatService.cs` and `ZavaStorefront.csproj`.
- Do **not** modify any file under `.github/agents/`.
- After implementing, confirm which files were changed and that no other files were touched.
