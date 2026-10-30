// -----------------------------------------------------------------------------
// Items Management (QR Menu) - compatibility layer for code ported from the
// old ASP.NET MVC 4 / .NET Framework 4.8 project (legacy/ItemManagement).
//
// It lets the ported controllers and views run with as few edits as possible,
// so the 80,000 lines of JavaScript they serve keep working unchanged:
//   * Json(...) answers exactly like MVC 4 did (PascalCase, \/Date()\/ dates)
//   * JSON request bodies bind to action parameters like MVC 4 did
//   * ConfigurationManager.AppSettings / ConnectionStrings  -> appsettings.json "QrMenu"
//   * Server.MapPath("~/x")                                   -> wwwroot-qr/x
//   * the old "eCommerceCook" cookie                         -> QrCookie, built from the
//                                                               HRMS sign-in + Security.Users
// Port a module at a time; when a module is rewritten natively it stops
// deriving from LegacyController and none of this is needed any more.
// -----------------------------------------------------------------------------
using System.Collections.Specialized;
using System.Globalization;
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Controllers;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.AspNetCore.Mvc.ModelBinding;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Primitives;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace HRMS.Web.Areas.Items.Legacy;

/// <summary>MVC 4's JsonRequestBehavior - accepted and ignored (GET is always allowed here).</summary>
public enum JsonRequestBehavior { AllowGet, DenyGet }

/// <summary>Settings shared by every legacy JSON response.</summary>
public static class LegacyJson
{
    public static readonly JsonSerializerSettings Settings = new()
    {
        // MVC 4's JavaScriptSerializer: property names as declared, dates as \/Date(ms)\/
        DateFormatHandling = DateFormatHandling.MicrosoftDateFormat,
        DateTimeZoneHandling = DateTimeZoneHandling.Utc,   // \/Date(ms)\/ with no offset, as MVC 4 wrote it
        ReferenceLoopHandling = ReferenceLoopHandling.Ignore,
        ContractResolver = new Newtonsoft.Json.Serialization.DefaultContractResolver()
    };
}

/// <summary>A JsonResult that writes with Newtonsoft and <see cref="LegacyJson.Settings"/>.</summary>
public sealed class LegacyJsonResult : JsonResult
{
    public LegacyJsonResult(object? value) : base(value) { }

    public override async Task ExecuteResultAsync(ActionContext context)
    {
        var response = context.HttpContext.Response;
        response.ContentType = "application/json; charset=utf-8";
        if (StatusCode.HasValue) response.StatusCode = StatusCode.Value;
        var text = JsonConvert.SerializeObject(Value, LegacyJson.Settings);
        await response.WriteAsync(text, Encoding.UTF8);
    }
}

/// <summary>Base class for controllers ported from the old project.</summary>
[Area("Items")]
public abstract class LegacyController : Controller
{
    public override JsonResult Json(object? data) => new LegacyJsonResult(data);

    protected JsonResult Json(object? data, JsonRequestBehavior behavior) => new LegacyJsonResult(data);

    protected JsonResult Json(object? data, string contentType) => new LegacyJsonResult(data);

    /// <summary>MVC 4's Server.MapPath, rooted at wwwroot-qr.</summary>
    protected LegacyServer Server => new(HttpContext.RequestServices.GetRequiredService<IWebHostEnvironment>());

    /// <summary>The signed-in QR Menu user, in the shape of the old eCommerceCook cookie; null when not signed in.</summary>
    protected QrCookie? QrCookie => QrCookie.For(HttpContext);

    public override void OnActionExecuting(ActionExecutingContext context)
    {
        // The old pages use inline <script> blocks and onclick="" handlers, which the
        // HRMS Content-Security-Policy blocks. Relax it for these responses only.
        LegacyCsp.Apply(context.HttpContext);
        base.OnActionExecuting(context);
    }
}

public static class LegacyCsp
{
    public static void Apply(HttpContext http)
    {
        http.Response.Headers["Content-Security-Policy"] = string.Join("; ",
            "default-src 'self'",
            "script-src 'self' 'unsafe-inline' 'unsafe-eval' https://cdn.datatables.net",
            "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://cdn.datatables.net",
            "font-src 'self' https://fonts.gstatic.com data:",
            "img-src 'self' data: blob: https:",
            "media-src 'self' blob:",
            "connect-src 'self'",
            "form-action 'self'",
            "frame-ancestors 'none'",
            "base-uri 'self'",
            "object-src 'none'");
    }
}

/// <summary>Where the old project's static files and uploads live (wwwroot-qr).</summary>
public static class QrStatic
{
    public const string FolderName = "wwwroot-qr";

    public static string Root(IWebHostEnvironment env) => Path.Combine(env.ContentRootPath, FolderName);
}

public sealed class LegacyServer
{
    private readonly IWebHostEnvironment _env;
    public LegacyServer(IWebHostEnvironment env) => _env = env;

    public string MapPath(string virtualPath)
    {
        var rel = (virtualPath ?? string.Empty).Replace('\\', '/').TrimStart('~').TrimStart('/');
        var root = QrStatic.Root(_env);
        var full = Path.GetFullPath(Path.Combine(root, rel.Replace('/', Path.DirectorySeparatorChar)));
        if (!full.StartsWith(Path.GetFullPath(root), StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Path is outside the QR Menu folder.");
        return full;
    }
}

/// <summary>HttpPostedFileBase members the old code used, on IFormFile.</summary>
public static class FormFileExtensions
{
    public static void SaveAs(this IFormFile file, string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        using var stream = File.Create(path);
        file.CopyTo(stream);
    }
}

/// <summary>System.Configuration.ConfigurationManager, read from appsettings.json.</summary>
public static class ConfigurationManager
{
    private static IConfiguration? _config;

    public static void Initialize(IConfiguration config) => _config = config;

    /// <summary>appsettings.json "QrMenu:AppSettings" - same keys as the old Web.config appSettings.</summary>
    public static NameValueCollection AppSettings
    {
        get
        {
            var nv = new NameValueCollection();
            if (_config is null) return nv;
            foreach (var kv in _config.GetSection("QrMenu:AppSettings").AsEnumerable(makePathsRelative: true))
                if (kv.Value is not null) nv[kv.Key] = kv.Value;
            return nv;
        }
    }

    public static LegacyConnectionStrings ConnectionStrings => new(_config);
}

public sealed class LegacyConnectionStrings
{
    private readonly IConfiguration? _config;
    public LegacyConnectionStrings(IConfiguration? config) => _config = config;

    /// <summary>
    /// The old names (ConnStr, POSConnection, SqlConnectionString) all point at the
    /// merged database: "ConnectionStrings:QrMenu" if set, else the HRMS
    /// "SqlServerConnectionString".
    /// </summary>
    public LegacyConnectionString this[string name]
    {
        get
        {
            var cs = _config?.GetConnectionString("QrMenu");
            if (string.IsNullOrWhiteSpace(cs)) cs = _config?.GetConnectionString("SqlServerConnectionString");
            if (string.IsNullOrWhiteSpace(cs)) return new LegacyConnectionString(string.Empty);
            // same transport settings as the rest of HRMS (appsettings.json "Database")
            var b = new Microsoft.Data.SqlClient.SqlConnectionStringBuilder(cs);
            if (_config!.GetValue("Database:TrustServerCertificate", true)) b.TrustServerCertificate = true;
            if (string.IsNullOrEmpty(b.ApplicationName) || b.ApplicationName == "Core Microsoft SqlClient Data Provider")
                b.ApplicationName = "HRMS.Web.QrMenu";
            return new LegacyConnectionString(b.ConnectionString);
        }
    }
}

public sealed record LegacyConnectionString(string ConnectionString);

/// <summary>System.Web.Script.Serialization.JavaScriptSerializer, on Newtonsoft.</summary>
public sealed class JavaScriptSerializer
{
    public int MaxJsonLength { get; set; }
    public string Serialize(object? obj) => JsonConvert.SerializeObject(obj, LegacyJson.Settings);
    public T Deserialize<T>(string input) => JsonConvert.DeserializeObject<T>(input, LegacyJson.Settings)!;
    public object? DeserializeObject(string input) => JsonConvert.DeserializeObject(input, LegacyJson.Settings);
}

/// <summary>
/// The old "eCommerceCook" cookie (UserName, Name, BrandID, RoleID, WaiterID, FeedBack,
/// MultipleBranch). The values now come from the HRMS sign-in (Security.Users) and the
/// user's QR role, read once per request - nothing is trusted from the browser.
/// </summary>
public sealed class QrCookie
{
    private readonly Dictionary<string, string> _values = new(StringComparer.OrdinalIgnoreCase);

    public string? this[string key] => _values.TryGetValue(key, out var v) ? v : null;

    public bool HasRole => !string.IsNullOrEmpty(this["RoleID"]) && this["RoleID"] != "0";

    public static QrCookie? For(HttpContext http)
    {
        if (http.Items.TryGetValue(typeof(QrCookie), out var cached)) return cached as QrCookie;

        QrCookie? result = null;
        var idText = http.User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (http.User.Identity?.IsAuthenticated == true && long.TryParse(idText, out var userId))
        {
            var ds = DB.GetData(
                "SELECT u.UserId, u.Username, ISNULL(u.DisplayName, u.Username) AS Name, ISNULL(u.BrandID, '0') AS BrandID, " +
                "ISNULL(qr.LegacyRoleId, 0) AS RoleID, ISNULL(b.FeedBack, 0) AS FeedBack, " +
                "ISNULL(b.MultipleBranch, 0) AS MultipleBranch " +
                "FROM Security.Users u " +
                "OUTER APPLY dbo.fn_QR_UserRole(u.UserId) qr " +
                "LEFT JOIN dbo.tblBrand b ON b.BrandID = TRY_CAST(u.BrandID AS INT) " +
                "WHERE u.UserId = " + userId.ToString(CultureInfo.InvariantCulture) + " AND u.Deleted = 0");
            if (ds.Tables.Count > 0 && ds.Tables[0].Rows.Count > 0)
            {
                var r = ds.Tables[0].Rows[0];
                result = new QrCookie();
                result._values["UserName"] = r["Username"].ToString()!;
                result._values["Name"] = r["Name"].ToString()!;
                result._values["BrandID"] = r["BrandID"].ToString()!;
                result._values["RoleID"] = r["RoleID"].ToString()!;
                result._values["WaiterID"] = r["UserId"].ToString()!;
                result._values["FeedBack"] = Convert.ToBoolean(r["FeedBack"]) ? "1" : "0";
                result._values["MultipleBranch"] = Convert.ToBoolean(r["MultipleBranch"]) ? "1" : "0";
            }
        }

        http.Items[typeof(QrCookie)] = result;
        return result;
    }
}

/// <summary>
/// MVC 4 bound JSON request bodies to action parameters by flattening them into
/// form-style keys ("value.Name", "list[0].Id"). This does the same for the
/// legacy controllers, so $.ajax({ contentType: 'application/json' }) calls work unchanged.
/// </summary>
public sealed class LegacyJsonBodyValueProviderFactory : IValueProviderFactory
{
    public async Task CreateValueProviderAsync(ValueProviderFactoryContext context)
    {
        var request = context.ActionContext.HttpContext.Request;
        if (context.ActionContext.ActionDescriptor is not ControllerActionDescriptor cad ||
            !typeof(LegacyController).IsAssignableFrom(cad.ControllerTypeInfo) ||
            request.ContentType is null ||
            !request.ContentType.Contains("json", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        request.EnableBuffering();
        string body;
        using (var reader = new StreamReader(request.Body, Encoding.UTF8, leaveOpen: true))
            body = await reader.ReadToEndAsync();
        request.Body.Position = 0;
        if (string.IsNullOrWhiteSpace(body)) return;

        JToken token;
        try { token = JToken.Parse(body); }
        catch (JsonReaderException) { return; }

        var values = new Dictionary<string, StringValues>(StringComparer.OrdinalIgnoreCase);
        Flatten(token, string.Empty, values);
        context.ValueProviders.Insert(0, new FormValueProvider(
            BindingSource.Form, new Microsoft.AspNetCore.Http.FormCollection(values), CultureInfo.InvariantCulture));
    }

    private static void Flatten(JToken token, string prefix, IDictionary<string, StringValues> values)
    {
        switch (token)
        {
            case JObject obj:
                foreach (var p in obj.Properties())
                    Flatten(p.Value, prefix.Length == 0 ? p.Name : prefix + "." + p.Name, values);
                break;
            case JArray arr:
                for (var i = 0; i < arr.Count; i++)
                    Flatten(arr[i], prefix + "[" + i.ToString(CultureInfo.InvariantCulture) + "]", values);
                break;
            case JValue v:
                string? text = v.Type switch
                {
                    JTokenType.Null or JTokenType.Undefined => null,
                    JTokenType.Boolean => (bool)v ? "true" : "false",
                    JTokenType.Date => ((DateTime)v).ToString("o", CultureInfo.InvariantCulture),
                    JTokenType.Float => Convert.ToString(v.Value, CultureInfo.InvariantCulture),
                    _ => Convert.ToString(v.Value, CultureInfo.InvariantCulture)
                };
                values[prefix] = text ?? string.Empty;
                break;
        }
    }
}

/// <summary>"~/x" + ?v=file timestamp, like the old Asset.V() helper.</summary>
public static class Asset
{
    private static IWebHostEnvironment? _env;
    public static void Initialize(IWebHostEnvironment env) => _env = env;

    public static string V(string path)
    {
        if (string.IsNullOrEmpty(path)) return path;
        var q = path.IndexOf('?');
        var clean = q >= 0 ? path[..q] : path;
        var url = clean.StartsWith("~/") ? clean[1..] : clean;
        if (_env is null) return url;
        var rel = url.TrimStart('/').Replace('/', Path.DirectorySeparatorChar);
        var candidates = new[] { Path.Combine(QrStatic.Root(_env), rel), Path.Combine(_env.WebRootPath ?? "", rel) };
        foreach (var file in candidates)
            if (File.Exists(file))
                return url + "?v=" + File.GetLastWriteTimeUtc(file).Ticks.ToString("x", CultureInfo.InvariantCulture);
        return url;
    }
}

public static class QrMenuLegacyRegistration
{
    /// <summary>Services and MVC options the ported Items Management code needs.</summary>
    public static IServiceCollection AddQrMenuLegacy(this IServiceCollection services, IConfiguration configuration)
    {
        ConfigurationManager.Initialize(configuration);
        services.Configure<MvcOptions>(o => o.ValueProviderFactories.Insert(0, new LegacyJsonBodyValueProviderFactory()));
        // The old upload screens send images and videos up to 50 MB.
        services.Configure<Microsoft.AspNetCore.Http.Features.FormOptions>(o => o.MultipartBodyLengthLimit = 52_428_800);
        return services;
    }

    /// <summary>Serves wwwroot-qr (the old project's css/js/images) after wwwroot.</summary>
    public static IApplicationBuilder UseQrMenuStaticFiles(this WebApplication app)
    {
        Asset.Initialize(app.Environment);
        var root = QrStatic.Root(app.Environment);
        Directory.CreateDirectory(root);
        app.UseStaticFiles(new StaticFileOptions
        {
            FileProvider = new PhysicalFileProvider(root),
            OnPrepareResponse = ctx => ctx.Context.Response.Headers.CacheControl = "public,max-age=604800"
        });
        return app;
    }
}
