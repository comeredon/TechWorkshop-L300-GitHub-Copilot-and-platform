using Microsoft.AspNetCore.Mvc;
using ZavaStorefront.Services;

namespace ZavaStorefront.Controllers;

public record GenerateImageRequest(int ProductId, string Description);

[IgnoreAntiforgeryToken]
public class ImageController : Controller
{
    private readonly ImageGenerationService _imageService;
    private readonly ILogger<ImageController> _logger;

    public ImageController(ImageGenerationService imageService, ILogger<ImageController> logger)
    {
        _imageService = imageService;
        _logger = logger;
    }

    [HttpPost]
    public async Task<IActionResult> Generate([FromBody] GenerateImageRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Description))
        {
            return BadRequest(new { error = "Description is required." });
        }

        _logger.LogInformation("GenerateImage: product={ProductId}", request.ProductId);

        var url = await _imageService.GenerateProductImageAsync(request.Description);

        if (url == null)
        {
            return StatusCode(422, new { error = "Content safety check prevented image generation." });
        }

        return Ok(new { imageUrl = url });
    }
}
