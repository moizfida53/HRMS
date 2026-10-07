using Microsoft.Extensions.Options;

namespace HRMS.Web.Services;

/// <summary>
/// Settings for where employee document uploads are kept - the
/// "DocumentStorage" section of appsettings.json.
/// </summary>
public sealed class DocumentStorageOptions
{
    public const string SectionName = "DocumentStorage";

    /// <summary>
    /// Folder that holds every uploaded file. Relative paths are resolved
    /// against the app's content root. Default App_Data/uploads - outside
    /// wwwroot on purpose, so a file is only reachable through the
    /// authenticated download action, never as a static URL.
    /// </summary>
    public string RootPath { get; set; } = "App_Data/uploads";

    /// <summary>Largest accepted file, in megabytes.</summary>
    public int MaxFileSizeMb { get; set; } = 5;
}

/// <summary>Outcome of validating and saving one upload.</summary>
public sealed record StoredDocument(
    string RelativePath, string OriginalFileName, string ContentType, long SizeBytes);

public interface IDocumentStorage
{
    long MaxFileSizeBytes { get; }

    /// <summary>
    /// Checks the file (extension AND content signature, size) and writes it
    /// under employees/{employeeId}/ with a random name. Returns an error
    /// message instead of throwing when the file is not acceptable.
    /// </summary>
    Task<(StoredDocument? Document, string? Error)> SaveAsync(
        long employeeId, IFormFile file, CancellationToken cancellationToken);

    /// <summary>Full path for a stored relative path, or null if it escapes the root or is missing.</summary>
    string? Resolve(string relativePath);
}

/// <summary>
/// Local-disk implementation. Uploaded names are never used on disk - only a
/// GUID plus the validated extension - and every path is re-checked to stay
/// inside the root before it is read.
/// </summary>
public sealed class LocalDocumentStorage : IDocumentStorage
{
    // Extension -> (content type, magic-byte check). The extension alone is
    // not trusted: a renamed .exe must not pass as a .pdf.
    private static readonly Dictionary<string, (string ContentType, Func<byte[], bool> Matches)> Allowed =
        new(StringComparer.OrdinalIgnoreCase)
        {
            [".pdf"]  = ("application/pdf", b => b.Length >= 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46), // %PDF
            [".jpg"]  = ("image/jpeg",      b => b.Length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF),
            [".jpeg"] = ("image/jpeg",      b => b.Length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF),
            [".png"]  = ("image/png",       b => b.Length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47
                                                                && b[4] == 0x0D && b[5] == 0x0A && b[6] == 0x1A && b[7] == 0x0A)
        };

    private readonly string _root;

    public LocalDocumentStorage(IOptions<DocumentStorageOptions> options, IWebHostEnvironment environment)
    {
        var value = options.Value;
        _root = Path.GetFullPath(Path.IsPathRooted(value.RootPath)
            ? value.RootPath
            : Path.Combine(environment.ContentRootPath, value.RootPath));
        MaxFileSizeBytes = Math.Max(1, value.MaxFileSizeMb) * 1024L * 1024L;
    }

    public long MaxFileSizeBytes { get; }

    public async Task<(StoredDocument? Document, string? Error)> SaveAsync(
        long employeeId, IFormFile file, CancellationToken cancellationToken)
    {
        if (file is null || file.Length == 0)
        {
            return (null, "Choose a file to upload.");
        }

        if (file.Length > MaxFileSizeBytes)
        {
            return (null, $"The file is {file.Length / 1024d / 1024d:0.0} MB - the limit is {MaxFileSizeBytes / 1024 / 1024} MB.");
        }

        var extension = Path.GetExtension(file.FileName);
        if (string.IsNullOrEmpty(extension) || !Allowed.TryGetValue(extension, out var rule))
        {
            return (null, "Only PDF, JPG or PNG files can be uploaded.");
        }

        var header = new byte[8];
        int read;
        await using (var probe = file.OpenReadStream())
        {
            read = await probe.ReadAsync(header.AsMemory(0, header.Length), cancellationToken);
        }

        if (!rule.Matches(header[..read]))
        {
            return (null, $"This file is not a real {extension.TrimStart('.').ToUpperInvariant()} file. Re-save it and try again.");
        }

        var relativeFolder = Path.Combine("employees", employeeId.ToString(System.Globalization.CultureInfo.InvariantCulture));
        var storedName = $"{Guid.NewGuid():N}{extension.ToLowerInvariant()}";
        var relativePath = Path.Combine(relativeFolder, storedName);
        var fullPath = Path.Combine(_root, relativePath);

        Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);

        await using (var target = new FileStream(fullPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
        {
            await file.CopyToAsync(target, cancellationToken);
        }

        // Keep the display name, but strip any path the browser may have sent.
        var originalName = Path.GetFileName(file.FileName);
        if (originalName.Length > 260)
        {
            originalName = originalName[^260..];
        }

        // Stored with forward slashes so the DB value is the same on any OS.
        return (new StoredDocument(relativePath.Replace('\\', '/'), originalName, rule.ContentType, file.Length), null);
    }

    public string? Resolve(string relativePath)
    {
        if (string.IsNullOrWhiteSpace(relativePath))
        {
            return null;
        }

        var fullPath = Path.GetFullPath(Path.Combine(_root, relativePath.Replace('/', Path.DirectorySeparatorChar)));
        var rootWithSeparator = _root.EndsWith(Path.DirectorySeparatorChar) ? _root : _root + Path.DirectorySeparatorChar;

        if (!fullPath.StartsWith(rootWithSeparator, StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        return File.Exists(fullPath) ? fullPath : null;
    }
}
