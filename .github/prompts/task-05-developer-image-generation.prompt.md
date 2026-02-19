---
mode: agent
agent: developer
description: Task 05 – Add AI-powered product image generation feature using gpt-image-1.5 (developer prompt)
---

# Task 05 – AI-Powered Product Image Generation

## Constraint
> **Do NOT modify any file under `.github/agents/`.** Agent definitions are managed separately and must not be altered by this prompt.

## Context
- App: ASP.NET Core (.NET 10), located in `src/`
- Authentication pattern: `CognitiveServicesCredential` — a private nested class that wraps `DefaultAzureCredential` and forces the `https://cognitiveservices.azure.com/.default` scope. It is already defined in `src/Services/ChatService.cs`. **Replicate this same pattern in the new service — do NOT introduce API keys and do NOT create a shared base class.**
- Config keys available as environment variables on the App Service:
  - `AZURE_AI_SERVICES_ENDPOINT` — Azure AI Services base endpoint (e.g. `https://aisXXXX.cognitiveservices.azure.com/`)
  - `AZURE_AI_IMAGE_DEPLOYMENT_NAME` — image generation deployment name (value: `gpt-image-1.5`), provisioned by the IaS task
- **Model note:** The deployed model is `gpt-image-1.5` (OpenAI format, GlobalStandard SKU, `westus3`). DALL-E 3 was not used because it is unavailable in `westus3` and deprecated as of 2026-03-04. The `Azure.AI.OpenAI` `ImageClient` API surface is identical — no code change is required compared to DALL-E 3.
- Existing services: `ChatService`, `ProductService`, `CartService`
- Content Safety: already used in `ChatService` (package: `Azure.AI.ContentSafety 1.0.0`). Reuse the same SDK and logging pattern in the new service.

Read `src/Program.cs`, `src/Services/ChatService.cs`, `src/ZavaStorefront.csproj`, `src/Controllers/HomeController.cs`, and `src/Views/Home/Index.cshtml` before making any changes.

---

## Requirements

### 1. Add NuGet Package

Add the following package to `src/ZavaStorefront.csproj` inside the existing `<ItemGroup>` that contains `<PackageReference>` entries:

```xml
<PackageReference Include="Azure.AI.OpenAI" Version="2.1.0" />
```

---

### 2. Create `src/Services/ImageGenerationService.cs`

Create a new file with the following implementation:

**Constructor:** Accept `IConfiguration config` and `ILogger<ImageGenerationService> logger`.

In the constructor:
- Read `AZURE_AI_SERVICES_ENDPOINT` (throw `InvalidOperationException` if missing — same pattern as `ChatService`).
- Read `AZURE_AI_IMAGE_DEPLOYMENT_NAME` (throw if missing).
- Instantiate a `CognitiveServicesCredential` (copy the nested class from `ChatService` verbatim into this class).
- Build an `AzureOpenAIClient` using the endpoint URI and credential.
- Call `client.GetImageClient(deploymentName)` to store an `ImageClient` field.
- Build a `ContentSafetyClient` using the AI Services endpoint URI and the same credential.

**Private nested class** (exact copy from `ChatService`):
```csharp
private sealed class CognitiveServicesCredential : TokenCredential
{
    private static readonly string[] Scopes = ["https://cognitiveservices.azure.com/.default"];
    private readonly DefaultAzureCredential _inner = new();

    public override AccessToken GetToken(TokenRequestContext _, CancellationToken ct)
        => _inner.GetToken(new TokenRequestContext(Scopes), ct);

    public override ValueTask<AccessToken> GetTokenAsync(TokenRequestContext _, CancellationToken ct)
        => _inner.GetTokenAsync(new TokenRequestContext(Scopes), ct);
}
```

**Public method:**

```csharp
public async Task<string?> GenerateProductImageAsync(string productDescription)
```

Implementation:
1. Build the generation prompt:
   ```
   "Product photo for an e-commerce store: {productDescription}. Clean white background, professional product photography style."
   ```
2. Run a content safety check on the prompt using the same pattern as `ChatService.CheckContentSafetyAsync` (inline — do not share the method). Log all four categories at Information level (`ContentSafety: category=X severity=Y`), then log the summary (`ContentSafety: result=PASS prompt_length=N` or `result=BLOCKED category=X severity=Y`). Treat severity **>= 2** as unsafe.
3. If content safety blocks the prompt, log a Warning (`"ImageGeneration: blocked by content safety for description length={length}"`) and return `null`.
4. Log the start of generation at Information level: `"ImageGeneration: generating image for description length={length}"`.
5. Call:
   ```csharp
   var result = await _imageClient.GenerateImageAsync(prompt, new ImageGenerationOptions
   {
       Size = GeneratedImageSize.W1024xH1024,
       Quality = GeneratedImageQuality.Standard,
       ResponseFormat = GeneratedImageFormat.Uri
   });
   ```
6. Log completion at Information level: `"ImageGeneration: image generated successfully"`.
7. Return `result.Value.ImageUri.ToString()`.
8. Do **not** catch and swallow exceptions — let them propagate.

---

### 3. Create `src/Controllers/ImageController.cs`

Create a new controller file. Define the request DTO in the same file.

**DTO:**
```csharp
public record GenerateImageRequest(int ProductId, string Description);
```

**Controller:**
- Inherit from `Controller`
- Decorate with `[IgnoreAntiforgeryToken]` (this endpoint receives AJAX requests with JSON body; the product descriptions are internal data, not user-supplied)
- Constructor: inject `ImageGenerationService imageService` and `ILogger<ImageController> logger`

**Action:** `POST /Image/Generate` — `[HttpPost]` attribute only (no explicit route; the default routing `{controller=Home}/{action=Index}` resolves to `/Image/Generate`)

Logic:
1. If `request.Description` is null or whitespace → return `BadRequest(new { error = "Description is required." })`.
2. Log at Information: `"GenerateImage: product={ProductId}"` using `request.ProductId`.
3. Call `await imageService.GenerateProductImageAsync(request.Description)`.
4. If the result is `null` → return `StatusCode(422, new { error = "Content safety check prevented image generation." })`.
5. Return `Ok(new { imageUrl = url })`.

---

### 4. Register the Service in `src/Program.cs`

After the existing `builder.Services.AddSingleton<ZavaStorefront.Services.ChatService>();` line, add:

```csharp
builder.Services.AddSingleton<ZavaStorefront.Services.ImageGenerationService>();
```

---

### 5. Update `src/Views/Home/Index.cshtml`

#### 5a. Outer layout

Replace the current top-level `<div class="container mt-4">` content with a two-column layout using a Bootstrap row:

```html
<div class="container mt-4">
    <h1 class="mb-4">Our Products</h1>

    <div class="row">
        <!-- Left sidebar: image generation controls -->
        <div class="col-md-2">
            <div class="d-grid gap-2">
                <button id="btnGenerateImages" class="btn btn-outline-primary">
                    <i class="bi bi-image"></i> Change Images
                </button>
            </div>
            <div id="imageGenerationStatus" class="mt-3 text-muted small" style="display:none;">
                <div class="spinner-border spinner-border-sm me-1" role="status" aria-hidden="true"></div>
                Your pictures are being generated...
            </div>
        </div>

        <!-- Right area: product grid -->
        <div class="col-md-10">
            <div class="row">
                @foreach (var product in Model)
                {
                    <div class="col-md-6 col-lg-4 mb-4">
                        <div class="card h-100">
                            <img src="@product.ImageUrl"
                                 class="card-img-top product-image"
                                 alt="@product.Name"
                                 data-product-id="@product.Id"
                                 data-description="@Html.AttributeEncode(product.Description)"
                                 onerror="this.src='https://via.placeholder.com/300x200?text=@Uri.EscapeDataString(product.Name)'">
                            <div class="card-body d-flex flex-column">
                                <h5 class="card-title">@product.Name</h5>
                                <p class="card-text flex-grow-1">@product.Description</p>
                                <div class="mt-auto">
                                    <p class="card-text"><strong>$@product.Price.ToString("F2")</strong></p>
                                    <form asp-controller="Home" asp-action="AddToCart" method="post">
                                        <input type="hidden" name="productId" value="@product.Id" />
                                        <button type="submit" class="btn btn-primary w-100">Buy</button>
                                    </form>
                                </div>
                            </div>
                        </div>
                    </div>
                }
            </div>
        </div>
    </div>
</div>
```

Key changes vs the original:
- Added the left sidebar column with the button and status message.
- Moved the product grid into a `col-md-10` right column.
- Added `data-product-id` and `data-description` attributes to each `<img>`.
- `onerror` fallback and other markup are otherwise unchanged.

#### 5b. JavaScript section

At the bottom of `Index.cshtml`, add a `@section Scripts {}` block:

```javascript
@section Scripts {
<script>
    document.getElementById('btnGenerateImages').addEventListener('click', async function () {
        const btn = this;
        const status = document.getElementById('imageGenerationStatus');

        btn.disabled = true;
        status.style.display = 'block';

        const images = document.querySelectorAll('img[data-product-id]');

        const tasks = Array.from(images).map(function (img) {
            const productId = parseInt(img.getAttribute('data-product-id'), 10);
            const description = img.getAttribute('data-description');

            return fetch('/Image/Generate', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ productId: productId, description: description })
            })
            .then(function (response) {
                if (!response.ok) return; // silent fallback — keep original image
                return response.json();
            })
            .then(function (data) {
                if (data && data.imageUrl) {
                    img.src = data.imageUrl;
                }
            })
            .catch(function () {
                // silent fallback — keep the original image on any network error
            });
        });

        await Promise.allSettled(tasks);

        status.style.display = 'none';
        btn.disabled = false;
    });
</script>
}
```

---

## Constraints
- Do **not** use API keys — use `CognitiveServicesCredential` with `DefaultAzureCredential` exclusively.
- Do **not** refactor, rename, or restructure any existing code.
- Do **not** store generated image URLs server-side — they are ephemeral (short-lived, from `gpt-image-1.5`) and are only held in the browser DOM during the session.
- Do **not** add new config keys — use only `AZURE_AI_SERVICES_ENDPOINT` and `AZURE_AI_IMAGE_DEPLOYMENT_NAME`.
- Do **not** catch and swallow `ImageGenerationService` exceptions.
- Do **not** modify any file under `.github/agents/`.
- After implementing, confirm which files were created or modified and that no other files were touched.

## Files to create or modify
| File | Action |
|------|--------|
| `src/ZavaStorefront.csproj` | Modified — new NuGet reference |
| `src/Services/ImageGenerationService.cs` | Created |
| `src/Controllers/ImageController.cs` | Created |
| `src/Program.cs` | Modified — register new service |
| `src/Views/Home/Index.cshtml` | Modified — new layout + JS |
