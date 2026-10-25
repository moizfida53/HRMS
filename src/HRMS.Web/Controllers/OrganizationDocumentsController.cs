using HRMS.Data.Repositories;
using HRMS.Domain.Organization;
using HRMS.Web.Models.Organization;
using HRMS.Web.Security;
using HRMS.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Workforce > Organizations (db/73): the active companies and their Legal & Compliance
/// Documents - number, dates, scan - renewed with history, and alerts before each expiry
/// date (the alerts are set per document type on Setup > Organization > Organization Documents).
/// A company opens in place (no id in the address).
/// </summary>
[Route("organizations")]
public sealed class OrganizationDocumentsController : Controller
{
    private const string PermView = "ORG_DOCUMENT_VIEW";
    private const string PermEdit = "ORG_DOCUMENT_EDIT";
    private const string PermDelete = "ORG_DOCUMENT_DELETE";
    private const string Views = "~/Views/OrganizationDocuments/";

    private readonly IOrganizationDocumentRepository _documents;
    private readonly IDocumentStorage _storage;
    private readonly ICurrentUser _currentUser;
    private readonly ICompanyFilter _companyFilter;
    private readonly ILogger<OrganizationDocumentsController> _logger;

    public OrganizationDocumentsController(IOrganizationDocumentRepository documents, IDocumentStorage storage,
        ICurrentUser currentUser, ICompanyFilter companyFilter, ILogger<OrganizationDocumentsController> logger)
    {
        _documents = documents;
        _storage = storage;
        _currentUser = currentUser;
        _companyFilter = companyFilter;
        _logger = logger;
    }

    private CancellationToken Ct => HttpContext.RequestAborted;
    private bool Can(string permission) => _currentUser.HasPermission(permission);
    private OrgDocumentRights Rights => new(Can(PermView) || Can(PermEdit), Can(PermEdit), Can(PermDelete));
    private OrgDocumentScope Scope => new(_currentUser.ActiveCompanyId, _companyFilter.Csv, _currentUser.UserId);
    private IActionResult Denied() => Json(ActionResponse.Failed("You do not have permission to do this.", "FORBIDDEN"));

    [HttpGet("")]
    public async Task<IActionResult> Index(int? company)
    {
        var r = Rights;
        if (!r.CanView) return Forbid();
        var companies = await _documents.CompaniesAsync(Scope, Ct);
        return View(Views + "Index.cshtml", new OrgDocumentsPageModel
        {
            Rights = r,
            Companies = companies,
            SelectedCompanyId = companies.Any(c => c.CompanyId == company) ? company : companies.FirstOrDefault()?.CompanyId
        });
    }

    /// <summary>The company list again (its counts change with every save).</summary>
    [HttpGet("companies")]
    public async Task<IActionResult> Companies()
    {
        if (!Rights.CanView) return Forbid();
        return PartialView(Views + "_CompanyList.cshtml", new OrgCompanyListModel { Companies = await _documents.CompaniesAsync(Scope, Ct) });
    }

    [HttpGet("panel")]
    public async Task<IActionResult> Panel(int company)
    {
        var r = Rights;
        if (!r.CanView) return Forbid();
        var summary = (await _documents.CompaniesAsync(Scope, Ct)).FirstOrDefault(c => c.CompanyId == company);
        if (summary is null) return NotFound();
        return PartialView(Views + "_CompanyDocuments.cshtml", new OrgCompanyDocumentsModel
        {
            Company = summary,
            Rows = await _documents.ListAsync(company, Scope, Ct),
            Rights = r
        });
    }

    /// <summary>Add / change a document, or renew it (a new version; the current one goes to its history).</summary>
    [HttpGet("form")]
    public async Task<IActionResult> Form(int company, int type, bool renew = false)
    {
        if (!Rights.CanEdit) return Forbid();
        var summary = (await _documents.CompaniesAsync(Scope, Ct)).FirstOrDefault(c => c.CompanyId == company);
        var row = summary is null ? null : (await _documents.ListAsync(company, Scope, Ct)).FirstOrDefault(x => x.OrgDocumentTypeId == type);
        if (summary is null || row is null) return NotFound();
        return PartialView(Views + "_DocumentForm.cshtml", new OrgDocumentFormModel
        {
            Company = summary,
            Row = row,
            Renew = renew && row.HasDocument,
            MaxFileSizeMb = (int)(_storage.MaxFileSizeBytes / 1024 / 1024)
        });
    }

    [HttpPost("save")]
    [RequestSizeLimit(20 * 1024 * 1024)]
    [RequestFormLimits(MultipartBodyLengthLimit = 20 * 1024 * 1024)]
    public async Task<IActionResult> Save(OrgDocumentInput input, IFormFile? file)
    {
        if (!Can(PermEdit)) return Denied();
        if (!ModelState.IsValid) return Json(ActionResponse.Failed("Check the fields and try again.", "VALIDATION"));

        // the company must be one the user may see (also checked by the procedure)
        if (!(await _documents.CompaniesAsync(Scope, Ct)).Any(c => c.CompanyId == input.CompanyId))
        {
            return Json(ActionResponse.Failed("That company was not found.", "NOT_FOUND"));
        }

        OrgDocumentFile? stored = null;
        if (file is { Length: > 0 })
        {
            var (doc, error) = await _storage.SaveToAsync(
                Path.Combine("companies", input.CompanyId.ToString(System.Globalization.CultureInfo.InvariantCulture)), file, Ct);
            if (doc is null)
            {
                return Json(ActionResponse.Invalid(new Dictionary<string, string[]> { ["file"] = [error ?? "The file could not be saved."] }));
            }
            stored = new OrgDocumentFile(doc.RelativePath, doc.OriginalFileName, doc.ContentType, doc.SizeBytes);
        }

        var result = await _documents.SaveAsync(input, stored, Scope, Ct);
        if (!result.Success && stored is not null)
        {
            // nothing points at the new file - don't leave it on disk
            var orphan = _storage.Resolve(stored.StoredFileName);
            if (orphan is not null) System.IO.File.Delete(orphan);
            _logger.LogInformation("Organization document save rejected with {Code}.", result.ErrorCode);
        }

        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    [HttpPost("delete")]
    public async Task<IActionResult> Delete(long id)
    {
        if (!Can(PermDelete)) return Denied();
        var result = await _documents.DeleteAsync(id, Scope, Ct);
        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    /// <summary>The current version and the ones its renewals archived.</summary>
    [HttpGet("history")]
    public async Task<IActionResult> History(int company, int type)
    {
        if (!Rights.CanView) return Forbid();
        var row = (await _documents.ListAsync(company, Scope, Ct)).FirstOrDefault(x => x.OrgDocumentTypeId == type);
        if (row is null) return NotFound();
        return PartialView(Views + "_History.cshtml", new OrgDocumentHistoryModel
        {
            Row = row,
            Versions = await _documents.HistoryAsync(company, type, Scope, Ct)
        });
    }

    /// <summary>A document's scan - inline to view, or as a download.</summary>
    [HttpGet("file")]
    public async Task<IActionResult> DocumentFile(long id, bool download = false)
    {
        if (!Rights.CanView) return Forbid();
        var doc = await _documents.GetAsync(id, Scope, Ct);
        var path = doc?.StoredFileName is { } stored ? _storage.Resolve(stored) : null;
        if (doc is null || path is null) return NotFound();

        // same lock-down as employee files: only this app may frame it, never cached
        Response.Headers["Content-Security-Policy"] =
            "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; object-src 'self'; frame-ancestors " + (download ? "'none'" : "'self'");
        Response.Headers["X-Frame-Options"] = download ? "DENY" : "SAMEORIGIN";
        Response.Headers["X-Content-Type-Options"] = "nosniff";
        Response.Headers.CacheControl = "private, no-store, max-age=0";
        return PhysicalFile(path, doc.ContentType ?? "application/octet-stream",
            fileDownloadName: download ? doc.OriginalFileName : null, enableRangeProcessing: true);
    }
}
