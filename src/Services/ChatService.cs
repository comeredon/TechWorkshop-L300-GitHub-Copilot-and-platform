using Azure.AI.Inference;
using Azure.Core;
using Azure.Identity;
using ZavaStorefront.Models;

namespace ZavaStorefront.Services
{
    public class ChatService
    {
        private readonly ChatCompletionsClient _client;
        private const string DeploymentName = "Phi-4-mini-instruct";

        // The Azure AI Inference SDK derives the OAuth2 scope from the endpoint URL, which
        // produces an invalid audience (e.g. "https://aiXXX.cognitiveservices.azure.com/models/.default").
        // This wrapper forces the correct audience so the App Service managed identity token
        // is accepted by Azure AI Services (disableLocalAuth: true — no API keys allowed).
        private sealed class CognitiveServicesCredential : TokenCredential
        {
            private static readonly string[] Scopes = ["https://cognitiveservices.azure.com/.default"];
            private readonly DefaultAzureCredential _inner = new();

            public override AccessToken GetToken(TokenRequestContext _, CancellationToken ct)
                => _inner.GetToken(new TokenRequestContext(Scopes), ct);

            public override ValueTask<AccessToken> GetTokenAsync(TokenRequestContext _, CancellationToken ct)
                => _inner.GetTokenAsync(new TokenRequestContext(Scopes), ct);
        }

        public ChatService(IConfiguration config, ProductService productService)
        {
            var endpoint = new Uri(config["AZURE_AI_INFERENCE_ENDPOINT"]
                ?? throw new InvalidOperationException("AZURE_AI_INFERENCE_ENDPOINT is not configured."));

            // Identity-only — the CognitiveServicesCredential wrapper uses DefaultAzureCredential
            // (App Service system-assigned managed identity in production, Azure CLI locally)
            // and enforces the https://cognitiveservices.azure.com audience so the token is
            // accepted by the endpoint. No API key is ever used (disableLocalAuth: true).
            _client = new ChatCompletionsClient(endpoint, new CognitiveServicesCredential(), new AzureAIInferenceClientOptions());

            // Build the product catalog at startup — captured once as a readonly list and
            // also tokenized into individual words for the server-side relevance guard.
            _products = productService.GetAllProducts();
            _productWordSet = new HashSet<string>(
                _products.SelectMany(p => p.Name.Split([' ', '-'], StringSplitOptions.RemoveEmptyEntries)),
                StringComparer.OrdinalIgnoreCase);
        }

        // Product names stored for the server-side relevance guard in GetResponseAsync.
        private readonly List<Product> _products;

        // Words extracted from all product names at startup — used for partial matching so
        // "headphones" and "wireless" correctly match "Wireless Noise-Canceling Headphones".
        private readonly HashSet<string> _productWordSet;

        // Words that always indicate a shopping context regardless of specific product names.
        private static readonly HashSet<string> _shoppingKeywords = new(StringComparer.OrdinalIgnoreCase)
        {
            "buy", "purchase", "price", "cost", "cheap", "expensive", "recommend", "suggest",
            "compare", "difference", "feature", "spec", "review", "worth", "order", "ship",
            "deliver", "return", "warranty", "stock", "available", "product", "item", "store",
            "shop", "cart", "deal", "discount", "sale", "gift"
        };

        private bool IsRelatedToStore(string message)
        {
            var words = message.Split([' ', ',', '.', '?', '!', '\n', '-'], StringSplitOptions.RemoveEmptyEntries);

            // Allow if any word from the message matches a word from any product name
            if (words.Any(w => w.Length >= 4 && _productWordSet.Contains(w)))
                return true;

            // Allow if the message contains a generic shopping keyword
            return words.Any(w => _shoppingKeywords.Contains(w));
        }

        // Static system prompt — kept minimal so the model focuses on the per-request
        // context injected in the user message turn rather than general knowledge.
        private const string SystemPromptBase =
            "You are a shopping assistant for ZavaStorefront. " +
            "Answer customer questions strictly and only from the product context provided to you. " +
            "Never use outside knowledge.";

        public async Task<string> GetResponseAsync(string userMessage)
        {
            // Server-side relevance guard: reject clearly off-topic requests before
            // they reach the model to prevent misuse.
            if (!IsRelatedToStore(userMessage))
            {
                return "I'm here to help you with ZavaStorefront products only. " +
                       "Is there anything I can help you find in our store?";
            }

            // Retrieval-grounded approach: inject the matching catalog entries directly
            // into the user message turn as the context. Small models (Phi-4-mini) follow
            // user-turn grounding constraints more reliably than system-prompt-only rules.
            var matchedProducts = FindRelevantProducts(userMessage);
            var contextLines = matchedProducts.Count > 0
                ? matchedProducts.Select(p => $"- {p.Name} (${p.Price:F2}): {p.Description}")
                : _products.Select(p => $"- {p.Name} (${p.Price:F2}): {p.Description}");

            var contextBlock = string.Join("\n", contextLines);

            // The grounded user message wraps the customer's question inside the catalog
            // context. The model is instructed to answer ONLY from that context block.
            // The customer's raw text is placed AFTER the context so it cannot override
            // the grounding instructions ahead of it (prompt injection mitigation).
            var groundedUserMessage =
                $"STORE CATALOG (answer ONLY from this — no outside knowledge):\n" +
                $"{contextBlock}\n\n" +
                $"Customer question: {userMessage}\n\n" +
                "Answer using only the catalog above. If the product is not listed, " +
                "say: \"That product is not available in our store.\"";

            var options = new ChatCompletionsOptions
            {
                Model = DeploymentName,
                Messages =
                {
                    new ChatRequestSystemMessage(SystemPromptBase),
                    new ChatRequestUserMessage(groundedUserMessage)
                },
                MaxTokens = 300,
                // Temperature 0 = deterministic, stays close to supplied facts.
                Temperature = 0
            };

            var response = await _client.CompleteAsync(options);
            return response.Value.Content;
        }

        // Returns products whose name contains any word from the user message (>= 4 chars).
        // This narrows the context so the model has fewer facts to drift from.
        private List<Product> FindRelevantProducts(string message)
        {
            var words = new HashSet<string>(
                message.Split([' ', ',', '.', '?', '!', '\n', '-'], StringSplitOptions.RemoveEmptyEntries)
                       .Where(w => w.Length >= 4),
                StringComparer.OrdinalIgnoreCase);

            return _products
                .Where(p => p.Name.Split([' ', '-'], StringSplitOptions.RemoveEmptyEntries)
                              .Any(nameWord => words.Contains(nameWord)))
                .ToList();
        }
    }
}
