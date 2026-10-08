using System.Threading.RateLimiting;
using HRMS.Data;
using HRMS.Web.Localization;
using HRMS.Web.Security;
using HRMS.Web.Services;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Authorization;
using Microsoft.AspNetCore.RateLimiting;

var builder = WebApplication.CreateBuilder(args);

// ---------------------------------------------------------------------------
// Local, per-developer configuration override
// ---------------------------------------------------------------------------
// appsettings.{Environment}.local.json is where a real connection string (or
// any other secret) belongs on a developer machine. It is matched by
// .gitignore ("appsettings.*.local.json") so it can never be committed, and
// it is loaded last, after User Secrets, so it wins if both are present -
// convenient when several developers share one checkout but each points at
// their own SQL Server instance. Entirely optional: its absence is silent.
builder.Configuration.AddJsonFile(
    $"appsettings.{builder.Environment.EnvironmentName}.local.json",
    optional: true,
    reloadOnChange: true);

// ---------------------------------------------------------------------------
// MVC
// ---------------------------------------------------------------------------
builder.Services.AddControllersWithViews(options =>
{
    // Anti-forgery validation is opt-out rather than opt-in: every unsafe verb
    // is protected unless an action explicitly says otherwise.
    options.Filters.Add(new AutoValidateAntiforgeryTokenAttribute());

    // Authentication is likewise opt-out. Every action requires a signed-in user
    // unless it carries [AllowAnonymous]. A new controller is protected the
    // moment it is created, rather than when someone remembers the attribute.
    options.Filters.Add(new AuthorizeFilter(
        new AuthorizationPolicyBuilder()
            .RequireAuthenticatedUser()
            .Build()));

    // Every JSON ActionResponse is translated to the user's language on the
    // way out (stored-procedure and validation messages are English at source).
    options.Filters.AddService<ActionResponseLocalizationFilter>();
})
// [Display(Name)] and validation messages read their text from Core.UiLabels.
.AddDataAnnotationsLocalization();

// The AJAX calls in organization.js send the token in this header.
builder.Services.AddAntiforgery(options =>
{
    options.HeaderName = "RequestVerificationToken";
    options.Cookie.HttpOnly = true;
    options.Cookie.SameSite = SameSiteMode.Strict;

    if (builder.Environment.IsDevelopment())
    {
        // `dotnet run` serves plain HTTP on the first launch, and both the
        // __Host- prefix and SecurePolicy.Always require HTTPS - the antiforgery
        // system throws rather than silently downgrading. Relax it for local work
        // only; production below keeps the hardened form.
        options.Cookie.Name = "Hrms-Antiforgery";
        options.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
    }
    else
    {
        options.Cookie.Name = "__Host-Hrms-Antiforgery";
        options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
    }
});

// ---------------------------------------------------------------------------
// Authentication - Module 1
// ---------------------------------------------------------------------------
builder.Services
    .AddOptions<AuthenticationPolicyOptions>()
    .Bind(builder.Configuration.GetSection(AuthenticationPolicyOptions.SectionName))
    .ValidateDataAnnotations();

builder.Services
    .AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(options =>
    {
        options.LoginPath = "/account/login";
        options.LogoutPath = "/account/logout";
        options.AccessDeniedPath = "/account/denied";
        options.ReturnUrlParameter = "returnUrl";

        // Sliding expiration keeps an active user signed in; an idle one is
        // signed out after the configured window.
        options.ExpireTimeSpan = TimeSpan.FromMinutes(
            builder.Configuration.GetValue("Authentication:SessionMinutes", 60));
        options.SlidingExpiration = true;

        options.Cookie.HttpOnly = true;                       // not readable from JavaScript
        options.Cookie.SameSite = SameSiteMode.Lax;           // Lax so the post-login redirect works
        options.Cookie.IsEssential = true;

        if (builder.Environment.IsDevelopment())
        {
            options.Cookie.Name = "Hrms-Auth";
            options.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
        }
        else
        {
            options.Cookie.Name = "__Host-Hrms-Auth";
            options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
        }

        // Security > Create Roles / Assign Roles apply to signed-in users within a minute.
        options.Events.OnValidatePrincipal = HRMS.Web.Security.PermissionRefresh.ValidateAsync;

        // An expired session should land on the login page with an explanation
        // rather than a bare redirect the user cannot interpret.
        options.Events.OnRedirectToLogin = context =>
        {
            if (context.Request.Headers.XRequestedWith == "XMLHttpRequest" ||
                context.Request.Headers.Accept.ToString().Contains("application/json", StringComparison.OrdinalIgnoreCase))
            {
                // AJAX calls get a status code, not an HTML login page.
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                return Task.CompletedTask;
            }

            context.Response.Redirect(context.RedirectUri);
            return Task.CompletedTask;
        };

        options.Events.OnRedirectToAccessDenied = context =>
        {
            if (context.Request.Headers.XRequestedWith == "XMLHttpRequest")
            {
                context.Response.StatusCode = StatusCodes.Status403Forbidden;
                return Task.CompletedTask;
            }

            context.Response.Redirect(context.RedirectUri);
            return Task.CompletedTask;
        };
    });

builder.Services.AddAuthorization();

// ---------------------------------------------------------------------------
// Rate limiting - outer defence against credential stuffing
// ---------------------------------------------------------------------------
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

    // Partitioned by client IP: 10 sign-in attempts per minute. The per-account
    // lockout in the database handles a distributed attack on one account; this
    // handles one host spraying many accounts.
    options.AddPolicy("login", context =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 10,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                QueueProcessingOrder = QueueProcessingOrder.OldestFirst
            }));
});

// ---------------------------------------------------------------------------
// Data access - stored procedures only (see HRMS.Data.Abstractions.ISqlExecutor)
// ---------------------------------------------------------------------------
builder.Services.AddHrmsDataAccess(builder.Configuration);

// ---------------------------------------------------------------------------
// Application services
// ---------------------------------------------------------------------------
builder.Services.AddHttpContextAccessor();
builder.Services.AddSingleton<IPasswordHasher, PasswordHasher>();
builder.Services.AddScoped<ISignInService, SignInService>();
builder.Services.AddScoped<ICurrentUser, ClaimsCurrentUser>();
builder.Services.AddScoped<ICompanyFilter, CookieCompanyFilter>();   // top-bar company filter (cookie)
builder.Services.AddScoped<IRefProtector, RefProtector>();             // opaque, user-bound references instead of ids in URLs

// Bilingual UI (English / Arabic): labels in Core.UiLabels, the user's choice
// in Security.Users.PreferredLanguage + the Hrms-Lang cookie. db/33.
builder.Services.AddHrmsLocalization();

// Employee document uploads (Documents tab) - files on disk, metadata in SQL.
builder.Services
    .AddOptions<DocumentStorageOptions>()
    .Bind(builder.Configuration.GetSection(DocumentStorageOptions.SectionName));
builder.Services.AddSingleton<IDocumentStorage, LocalDocumentStorage>();

// Payslip emails (db/42-43) - queued from Payroll > Payslips, sent in the background.
builder.Services
    .AddOptions<PayslipEmailOptions>()
    .Bind(builder.Configuration.GetSection(PayslipEmailOptions.SectionName));
builder.Services.AddHostedService<PayslipEmailSender>();

// Figures next to Payroll Processing's sub-sections in the sidebar (cached a few seconds).
builder.Services.AddMemoryCache();
builder.Services.AddScoped<IPayrollNavCounts, PayrollNavCounts>();

builder.Services.AddResponseCompression();

var app = builder.Build();

if (app.Configuration.GetValue<bool>("Authentication:SimplePassword"))
{
    app.Logger.LogWarning(
        "Authentication:SimplePassword is ON - passwords are stored in plain text in Security.Users.[Password]. " +
        "Turn it off for production.");
}

// ---------------------------------------------------------------------------
// Pipeline
// ---------------------------------------------------------------------------
if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
}
else
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseSecurityHeaders();          // see Security/SecurityHeadersMiddleware.cs
app.UseResponseCompression();

app.UseStaticFiles(new StaticFileOptions
{
    OnPrepareResponse = context =>
    {
        // Long cache for fingerprinted assets; the layout appends asp-append-version.
        context.Context.Response.Headers.CacheControl = "public,max-age=604800";
    }
});

app.UseHrmsLanguage();             // UI culture from the Hrms-Lang cookie; keeps the label cache fresh
app.UseRouting();
app.UseRateLimiter();

app.UseAuthentication();
app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Dashboard}/{action=Index}/{id?}");

app.Run();
