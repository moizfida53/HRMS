using System.ComponentModel.DataAnnotations;

namespace HRMS.Data.Infrastructure;

public sealed class SqlServerOptions
{
    /// <summary>Section holding every non-secret database setting.</summary>
    public const string SectionName = "Database";

    /// <summary>
    /// Name of the entry under the standard "ConnectionStrings" section that
    /// supplies the actual connection string, e.g.
    /// ConnectionStrings:SqlServerConnectionString. Kept as the ordinary
    /// ASP.NET Core convention (IConfiguration.GetConnectionString) rather
    /// than a bespoke key, so it is supplied from wherever your team already
    /// supplies connection strings: an appsettings.{Environment}.local.json
    /// file (git-ignored - see .gitignore), User Secrets, or the
    /// ConnectionStrings__SqlServerConnectionString environment variable in
    /// production. It must never be committed in appsettings.json or
    /// appsettings.{Environment}.json.
    /// </summary>
    public const string ConnectionStringName = "SqlServerConnectionString";

    /// <summary>
    /// Populated from ConnectionStrings:SqlServerConnectionString - see
    /// <see cref="ConnectionStringName"/>. Not bound directly from the
    /// "Database" section; HRMS.Data.DependencyInjection wires this up
    /// explicitly via IConfiguration.GetConnectionString.
    /// </summary>
    // The literal braces around "Environment" are doubled ({{ }}) because
    // ValidationAttribute runs this message through string.Format when the
    // failure is reported - a single, unescaped "{Environment}" is parsed
    // as a composite format placeholder and throws a FormatException
    // ("Expected an ASCII digit") instead of showing this message, which
    // is exactly backwards for a message whose whole job is to explain a
    // missing connection string at startup.
    [Required(ErrorMessage = "ConnectionStrings:SqlServerConnectionString is not configured. Set it in appsettings.{{Environment}}.local.json, User Secrets, or the ConnectionStrings__SqlServerConnectionString environment variable.")]
    public string ConnectionString { get; set; } = string.Empty;

    /// <summary>Command timeout in seconds for every stored-procedure call.</summary>
    [Range(1, 600)]
    public int CommandTimeoutSeconds { get; set; } = 30;

    /// <summary>
    /// Forces Encrypt=True on the connection regardless of what the supplied
    /// connection string says. Leave on. Only turn it off for a local instance
    /// that genuinely has no certificate.
    /// </summary>
    public bool ForceEncryption { get; set; } = true;

    /// <summary>
    /// When true, allows a self-signed / untrusted server certificate.
    /// Must stay false in any environment that handles real employee data.
    /// </summary>
    public bool TrustServerCertificate { get; set; }

    /// <summary>Shown in SQL Server session DMVs - makes app traffic identifiable during audits.</summary>
    public string ApplicationName { get; set; } = "HRMS.Web";
}
