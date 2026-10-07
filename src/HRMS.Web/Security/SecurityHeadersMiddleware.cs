namespace HRMS.Web.Security;

/// <summary>
/// Response headers that a vulnerability scan will look for. Applied to every
/// response from one place, so no controller can forget them.
/// </summary>
public sealed class SecurityHeadersMiddleware
{
    private readonly RequestDelegate _next;
    private readonly IWebHostEnvironment _environment;

    public SecurityHeadersMiddleware(RequestDelegate next, IWebHostEnvironment environment)
    {
        _next = next;
        _environment = environment;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var headers = context.Response.Headers;

        // Stop MIME sniffing turning an upload into an executable script.
        headers["X-Content-Type-Options"] = "nosniff";

        // Legacy clickjacking defence; CSP frame-ancestors below covers modern ones.
        headers["X-Frame-Options"] = "DENY";

        // Do not leak internal URLs (which contain record ids) to third parties.
        headers["Referrer-Policy"] = "strict-origin-when-cross-origin";

        // Turn off browser features the application never uses.
        headers["Permissions-Policy"] =
            "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()";

        // Content Security Policy.
        // 'unsafe-inline' on style-src is required by Bootstrap's own inline
        // styles on modals and by the inline width styles the grid emits.
        // Scripts do NOT get 'unsafe-inline' - all page scripts are external
        // files, which is what keeps a reflected-XSS payload from executing.
        var csp = string.Join("; ",
            "default-src 'self'",
            "script-src 'self'",
            "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
            "font-src 'self' https://fonts.gstatic.com data:",
            "img-src 'self' data:",
            "connect-src 'self'",
            "form-action 'self'",
            "frame-ancestors 'none'",
            "base-uri 'self'",
            "object-src 'none'",
            _environment.IsDevelopment() ? null : "upgrade-insecure-requests");

        headers["Content-Security-Policy"] = csp.TrimEnd(';', ' ');

        // Remove server fingerprinting where the host lets us.
        headers.Remove("Server");
        headers.Remove("X-Powered-By");

        // Never let a browser or intermediary cache a page rendered for a signed-in
        // user, or the sign-in page itself. Without this, pressing Back after
        // signing out can redisplay employee data from the bfcache. Static files
        // are served earlier in the pipeline and keep their long cache headers.
        context.Response.OnStarting(() =>
        {
            var contentType = context.Response.ContentType;

            if (contentType is not null &&
                contentType.Contains("text/html", StringComparison.OrdinalIgnoreCase))
            {
                headers.CacheControl = "no-store, no-cache, must-revalidate, max-age=0";
                headers.Pragma = "no-cache";
                headers.Expires = "0";
            }

            return Task.CompletedTask;
        });

        await _next(context);
    }
}

public static class SecurityHeadersMiddlewareExtensions
{
    public static IApplicationBuilder UseSecurityHeaders(this IApplicationBuilder app) =>
        app.UseMiddleware<SecurityHeadersMiddleware>();
}
