using Microsoft.AspNetCore.Mvc;
using ZavaStorefront.Services;

namespace ZavaStorefront.Controllers
{
    public class ChatController : Controller
    {
        private readonly ChatService _chatService;

        public ChatController(ChatService chatService)
        {
            _chatService = chatService;
        }

        // POST /chat/send
        // Accepts a JSON body { "message": "..." } and returns { "reply": "..." }
        // No antiforgery token required — no server-side state is mutated on behalf of the user.
        [HttpPost]
        public async Task<IActionResult> Send([FromBody] ChatMessageRequest request)
        {
            if (string.IsNullOrWhiteSpace(request?.Message))
                return BadRequest(new { error = "Message cannot be empty." });

            // Limit input length to prevent excessive token usage
            var message = request.Message.Trim();
            if (message.Length > 1000)
                message = message[..1000];

            var reply = await _chatService.GetResponseAsync(message);
            return Json(new { reply });
        }
    }

    public record ChatMessageRequest(string Message);
}
