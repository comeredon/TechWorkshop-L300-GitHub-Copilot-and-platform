# Workspace Instructions

## Project Overview

This is an **L300-level workshop repository** teaching Azure modernization with GitHub Copilot and GitHub Enterprise. The scenario follows "Zava" - a retail chain developing an AI-powered e-commerce storefront. This is an **educational project** with 7 progressive exercises guiding learners through:

- Setting up development environments with Copilot
- Implementing Infrastructure as Code with Bicep
- Building CI/CD pipelines with GitHub Actions
- Applying GitHub Advanced Security features
- Integrating AI services (Azure OpenAI, Azure AI)
- Monitoring and governance

**Primary Application:** ASP.NET Core MVC (.NET 10.0) web storefront with AI chatbot and image generation capabilities.

**Infrastructure:** Azure services deployed via Bicep (App Service, AI Foundry, Container Registry, monitoring stack).

## Technology Stack

- **Backend:** ASP.NET Core MVC (.NET 10.0), C# with nullable reference types
- **AI Services:** Azure AI Inference (Phi-4-mini-instruct), Azure OpenAI (DALL-E 3, GPT-4o), Azure Content Safety
- **Authentication:** Azure Managed Identity (RBAC, zero secrets)
- **Containerization:** Docker (multi-stage builds)
- **Infrastructure:** Bicep modules with modular architecture
- **CI/CD:** GitHub Actions with OIDC authentication
- **Monitoring:** Application Insights, Log Analytics, Azure Workbooks

## Getting Started

### Build & Run Commands

```powershell
# Build the application
cd src
dotnet build

# Run locally
dotnet run

# Build Docker image
docker build -t zava-storefront ./src

# Deploy to Azure (provision + deploy)
azd up

# Get deployed service URL
azd env get-values | Select-String "SERVICE_WEB_URI"
```

### Project Structure

```
src/                      # ASP.NET Core web application
  Controllers/            # MVC controllers (Home, Cart, Chat, Image)
  Services/               # Business logic and AI integrations
  Models/                 # Data models
  Views/                  # Razor views
  wwwroot/                # Static assets
infra/                    # Bicep infrastructure templates
  modules/                # Reusable Bicep modules
docs/                     # Workshop exercises (01-07)
.github/workflows/        # GitHub Actions CI/CD
```

## Code Conventions & Patterns

### Architecture

- **Pattern:** ASP.NET Core MVC with Dependency Injection
- **Service Lifetimes:**
  - `Singleton`: ProductService (static data), AI services (expensive initialization)
  - `Scoped`: CartService (per-request session state)
- **Session Management:** Server-side session storage with 30-minute timeout
- **Error Handling:** Catch exceptions at controller level, return user-friendly messages

### AI Service Integration

#### 🚨 CRITICAL: Custom Credential Wrapper

Both [ChatService](../src/Services/ChatService.cs) and [ImageGenerationService](../src/Services/ImageGenerationService.cs) use a custom `CognitiveServicesCredential` class:

```csharp
private sealed class CognitiveServicesCredential : TokenCredential
{
    private static readonly string[] Scopes = ["https://cognitiveservices.azure.com/.default"];
    private readonly DefaultAzureCredential _inner = new();
    // Forces correct OAuth2 audience for Azure AI Services
}
```

**Why this matters:** Azure AI SDKs derive OAuth2 scope from endpoint URL incorrectly. This wrapper forces `https://cognitiveservices.azure.com/.default` so tokens are accepted when `disableLocalAuth: true` (keyless auth). **Do not remove this wrapper** or managed identity authentication will fail.

#### Content Safety Pattern

All user inputs pass through Azure Content Safety API before AI model invocation:

```csharp
foreach (var category in result.CategoriesAnalysis)
{
    if (category.Severity >= 2) {  // Block threshold
        _logger.LogInformation("ContentSafety: result=BLOCKED category={Category}...");
        return "I'm sorry, I can't help with that...";
    }
}
```

- **Threshold:** Severity >= 2 blocks request
- **Categories checked:** Violence, Sexual, SelfHarm, Hate
- **Applied in:** ChatService (user messages), ImageGenerationService (prompts)

#### Retrieval-Grounded Generation (RAG)

ChatService implements a grounded approach to prevent hallucination:

1. Server-side relevance guard filters off-topic queries
2. Product catalog injected into system prompt
3. **User text placed AFTER context** (prompt injection mitigation)
4. Temperature = 0 (deterministic, factual responses)

**Do not reorder prompt structure** - the sequence prevents jailbreak attempts.

#### AI Configuration

All endpoints come from environment variables:

```csharp
var endpoint = new Uri(config["AZURE_AI_INFERENCE_ENDPOINT"]
    ?? throw new InvalidOperationException("Missing AZURE_AI_INFERENCE_ENDPOINT"));
```

- `AZURE_AI_INFERENCE_ENDPOINT` - Phi-4-mini-instruct chat endpoint
- `AZURE_AI_CONTENTSAFETY_ENDPOINT` - Content Safety API
- `AZURE_AI_IMAGE_ENDPOINT` - DALL-E 3 endpoint

### Coding Conventions

- **Naming:** `_privateField` (underscore prefix), `PascalCase` for public members
- **Modern C# features:** Records, primary constructors, collection expressions `[...]`, range syntax `message[..1000]`
- **Logging:** Structured logging with named parameters: `_logger.LogInformation("Action {Param}", value)`
- **Validation:** Early validation with early returns, silent truncation when appropriate
- **Anti-forgery:** Disabled on AI endpoints (stateless operations) via `[IgnoreAntiforgeryToken]`

## Infrastructure Patterns

### Bicep Conventions

- **Scope:** Subscription-level orchestrator ([main.bicep](../infra/main.bicep)), resource group-level modules
- **Naming:** Resource type prefix + uniqueString token (e.g., `law-`, `appi-`, `app-`)
- **Parameters:** Environment variables via `readEnvironmentVariable('AZURE_ENV_NAME', 'dev')`
- **Dependencies:** Explicit `dependsOn` for sequential deployments, especially AI model deployments
- **Security:** `disableLocalAuth: true` everywhere, RBAC roles for all access

### Module Organization

Each module implements one logical service with consistent interface:

```bicep
param name string
param location string
param tags object = {}
// + module-specific params
```

**Key Modules:**
- [loganalytics.bicep](../infra/modules/loganalytics.bicep) - Foundation for monitoring
- [aifoundry.bicep](../infra/modules/aifoundry.bicep) - Complex: storage, Key Vault, AI services, model deployments
- [appservice.bicep](../infra/modules/appservice.bicep) - App Service + ACR integration
- [aifoundry-appservice-rbac.bicep](../infra/modules/aifoundry-appservice-rbac.bicep) - RBAC assignments (breaks circular dependencies)

### Managed Identity & RBAC

All authentication uses system-assigned managed identities:

- **App Service → ACR:** `AcrPull` role
- **App Service → AI Services:** `Cognitive Services User` role
- **Hub → Key Vault/Storage:** Auto-created by Azure AI Foundry (not in Bicep)

**Zero secrets stored:** No API keys, passwords, or connection strings in code or configuration.

## Important Constraints & Pitfalls

### 🚨 Critical Issues

1. **Do not remove CognitiveServicesCredential wrapper** - Required for managed identity with Azure AI SDKs
2. **Do not reorder ChatService prompt structure** - User input must come AFTER grounding context
3. **Do not change Content Safety threshold** without business approval - Hardcoded severity >= 2
4. **Do not modify AI service lifetimes** - Singletons optimize expensive credential initialization
5. **Sequential AI model deployments** - Models in same account need `dependsOn` to avoid conflicts

### ⚠️ Known Limitations

- **Static product data:** ProductService uses in-memory list (not production-ready)
- **Session storage:** Server memory only (lost on restart, not multi-instance compatible)
- **Region split:** DALL-E 3 in `swedencentral`, other services in `westus3` (availability constraint)
- **Beta SDK:** Azure.AI.Inference is pre-release (potential breaking changes)

### Configuration Notes

- **App Service deployment:** `linuxFxVersion` managed by `azd deploy`, intentionally omitted from Bicep
- **Environment-specific params:** Use `.bicepparam` files with environment variable references
- **Diagnostic settings:** Comprehensive logging enabled (Audit, RequestResponse, Usage, Trace)

## Testing Approach

- **Manual testing:** Run locally via `dotnet run` or `docker run`
- **Build validation:** GitHub Actions runs on every PR
- **Integration testing:** Deploy to Azure and verify endpoints
- **Monitoring:** Application Insights telemetry for production behavior

No unit test project currently exists. When adding tests:
- Use `xunit` framework (standard for .NET)
- Test service logic independently of controllers
- Mock AI services to avoid external dependencies
- Test content safety threshold logic

## Workshop Context

This repository supports **7 progressive exercises**:

1. **Development Environment Setup** - GitHub Enterprise, VS Code, extensions
2. **Implement Infrastructure with Copilot** - Bicep generation with Azure MCP
3. **GitHub Actions CI/CD Pipeline** - Build and deploy workflows
4. **GitHub Advanced Security** - Dependabot, secret scanning, code scanning
5. **Integrate GitHub Copilot** - AI chatbot development, refactoring
6. **AI Governance & Observability** - Azure Monitor, Application Insights
7. **Resource Cleanup** - Azure resource management

**When assisting with workshop tasks:**
- Explain concepts pedagogically (this is for learning)
- Reference relevant exercise docs in [docs/](../docs/) folder
- Highlight GitHub Copilot features being demonstrated
- Emphasize security best practices (managed identity, content safety, RBAC)

## Common Tasks

### Adding a New AI Service

1. Add NuGet package to [ZavaStorefront.csproj](../src/ZavaStorefront.csproj)
2. Create service class in [Services/](../src/Services/) folder
3. Use `CognitiveServicesCredential` wrapper for Azure AI services
4. Add Content Safety checks for user inputs
5. Register in [Program.cs](../src/Program.cs) with appropriate lifetime
6. Add environment variable to [main.bicep](../infra/main.bicep) app settings
7. Update RBAC in [aifoundry-appservice-rbac.bicep](../infra/modules/aifoundry-appservice-rbac.bicep)

### Updating Bicep Infrastructure

1. Modify module in [infra/modules/](../infra/modules/)
2. Update [main.bicep](../infra/main.bicep) if new outputs needed
3. Validate: `az bicep build --file infra/main.bicep`
4. Deploy: `azd provision` or `azd up`
5. Verify in Azure Portal and check diagnostic logs

### Adding GitHub Actions Workflow

1. Create workflow in `.github/workflows/`
2. Use OIDC authentication (no stored secrets)
3. Required permissions: `contents: read`, `id-token: write`
4. Reference existing [deploy-zava.yml](../.github/workflows/deploy-zava.yml) for patterns
5. Test on feature branch before merging

## Documentation

- **Workshop exercises:** [docs/](../docs/) folder (markdown with step-by-step instructions)
- **Infrastructure docs:** Inline comments in Bicep files explain architectural decisions
- **Service docs:** C# XML documentation comments in service classes
- **GitHub Pages:** Jekyll site configured via [_config.yml](../_config.yml)

## Resources

- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [Azure AI Foundry](https://learn.microsoft.com/azure/ai-studio/)
- [GitHub Copilot for Business](https://github.com/features/copilot)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
