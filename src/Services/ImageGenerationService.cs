using Azure.AI.ContentSafety;
using Azure.AI.OpenAI;
using Azure.Core;
using Azure.Identity;
using OpenAI.Images;

namespace ZavaStorefront.Services
{
    public class ImageGenerationService
    {
        private readonly ImageClient _imageClient;
        private readonly ContentSafetyClient _contentSafetyClient;
        private readonly ILogger<ImageGenerationService> _logger;

        // The Azure AI OpenAI SDK derives the OAuth2 scope from the endpoint URL, which
        // produces an invalid audience. This wrapper forces the correct audience so the
        // App Service managed identity token is accepted by Azure AI Services
        // (disableLocalAuth: true — no API keys allowed).
        private sealed class CognitiveServicesCredential : TokenCredential
        {
            private static readonly string[] Scopes = ["https://cognitiveservices.azure.com/.default"];
            private readonly DefaultAzureCredential _inner = new();

            public override AccessToken GetToken(TokenRequestContext _, CancellationToken ct)
                => _inner.GetToken(new TokenRequestContext(Scopes), ct);

            public override ValueTask<AccessToken> GetTokenAsync(TokenRequestContext _, CancellationToken ct)
                => _inner.GetTokenAsync(new TokenRequestContext(Scopes), ct);
        }

        public ImageGenerationService(IConfiguration config, ILogger<ImageGenerationService> logger)
        {
            _logger = logger;

            try
            {
                var endpoint = new Uri(config["AZURE_AI_SERVICES_ENDPOINT"]
                    ?? throw new InvalidOperationException("AZURE_AI_SERVICES_ENDPOINT is not configured."));

                var deploymentName = config["AZURE_AI_IMAGE_DEPLOYMENT_NAME"]
                    ?? throw new InvalidOperationException("AZURE_AI_IMAGE_DEPLOYMENT_NAME is not configured.");

                _logger.LogInformation("ImageGenerationService: initializing with endpoint={Endpoint} deployment={Deployment}", 
                    endpoint, deploymentName);

                var credential = new CognitiveServicesCredential();

                // Identity-only — the CognitiveServicesCredential wrapper uses DefaultAzureCredential
                // (App Service system-assigned managed identity in production, Azure CLI locally)
                // and enforces the https://cognitiveservices.azure.com audience so the token is
                // accepted by the endpoint. No API key is ever used (disableLocalAuth: true).
                var client = new AzureOpenAIClient(endpoint, credential);
                _imageClient = client.GetImageClient(deploymentName);
                _contentSafetyClient = new ContentSafetyClient(endpoint, credential);

                _logger.LogInformation("ImageGenerationService: initialized successfully");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "ImageGenerationService: failed to initialize - {Error}", ex.Message);
                throw;
            }
        }

        public async Task<string?> GenerateProductImageAsync(string productDescription)
        {
            // Build the generation prompt
            var prompt = $"Product photo for an e-commerce store: {productDescription}. Clean white background, professional product photography style.";

            // Content safety check (inline — same pattern as ChatService)
            var request = new AnalyzeTextOptions(prompt);
            var response = await _contentSafetyClient.AnalyzeTextAsync(request);
            var result = response.Value;

            // Log all category scores
            _logger.LogInformation("ContentSafety: category=Violence severity={Severity}", 
                result.CategoriesAnalysis.FirstOrDefault(c => c.Category == TextCategory.Violence)?.Severity ?? 0);
            _logger.LogInformation("ContentSafety: category=Sexual severity={Severity}", 
                result.CategoriesAnalysis.FirstOrDefault(c => c.Category == TextCategory.Sexual)?.Severity ?? 0);
            _logger.LogInformation("ContentSafety: category=SelfHarm severity={Severity}", 
                result.CategoriesAnalysis.FirstOrDefault(c => c.Category == TextCategory.SelfHarm)?.Severity ?? 0);
            _logger.LogInformation("ContentSafety: category=Hate severity={Severity}", 
                result.CategoriesAnalysis.FirstOrDefault(c => c.Category == TextCategory.Hate)?.Severity ?? 0);

            // Check for violations (severity >= 2)
            foreach (var category in result.CategoriesAnalysis)
            {
                if (category.Severity >= 2)
                {
                    _logger.LogInformation("ContentSafety: result=BLOCKED category={Category} severity={Severity}", 
                        category.Category, category.Severity);
                    _logger.LogWarning("ImageGeneration: blocked by content safety for description length={Length}", 
                        productDescription.Length);
                    return null;
                }
            }

            _logger.LogInformation("ContentSafety: result=PASS prompt_length={Length}", prompt.Length);

            // Generate the image
            _logger.LogInformation("ImageGeneration: generating image for description length={Length}", 
                productDescription.Length);

            try
            {
                var imageResult = await _imageClient.GenerateImageAsync(prompt);
                
                _logger.LogInformation("ImageGeneration: image generated successfully");

                return imageResult.Value.ImageUri?.ToString();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "ImageGeneration: failed to generate image - {Error}", ex.Message);
                throw;
            }
        }
    }
}
