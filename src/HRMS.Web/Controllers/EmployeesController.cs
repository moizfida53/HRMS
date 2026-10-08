using HRMS.Data.Infrastructure;
using HRMS.Data.Repositories;
using HRMS.Domain.Common;
using HRMS.Domain.Workforce;
using HRMS.Web.Models.Organization;
using HRMS.Web.Models.Workforce;
using HRMS.Web.Security;
using HRMS.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Workforce - Employees &amp; Kuwait Compliance. One employee list grid,
/// and one Employee Profile page per employee with tabbed sections
/// (Personal Info, Employment, Kuwait Compliance, Documents), rather than
/// Organization Setup's "tabs switch between eight different masters" -
/// here every tab but Kuwait Compliance is the same underlying row.
/// </summary>
[Route("employees")]
public sealed class EmployeesController : Controller
{
    private readonly IEmployeeRepository _employees;
    private readonly IEmployeeComplianceRepository _compliance;
    private readonly IEmployeeDependentRepository _dependents;
    private readonly IEmployeeDocumentRepository _documents;
    private readonly IDocumentStorage _storage;
    private readonly ILookupRepository _lookups;
    private readonly ICurrentUser _currentUser;
    private readonly ICompanyFilter _companyFilter;
    private readonly ILogger<EmployeesController> _logger;

    /// <summary>Dropdowns the Personal Info and Employment tabs need on the profile screen.</summary>
    private static readonly string[] ProfileLookupTypes =
    [
        LookupType.Company, LookupType.Branch, LookupType.Department, LookupType.Section,
        LookupType.JobPosition, LookupType.Designation, LookupType.Grade, LookupType.CostCenter,
        LookupType.Location, LookupType.Country, LookupType.Employee
    ];

    public EmployeesController(
        IEmployeeRepository employees,
        IEmployeeComplianceRepository compliance,
        IEmployeeDependentRepository dependents,
        IEmployeeDocumentRepository documents,
        IDocumentStorage storage,
        ILookupRepository lookups,
        ICurrentUser currentUser,
        ICompanyFilter companyFilter,
        ILogger<EmployeesController> logger)
    {
        _employees = employees;
        _compliance = compliance;
        _dependents = dependents;
        _documents = documents;
        _storage = storage;
        _lookups = lookups;
        _currentUser = currentUser;
        _companyFilter = companyFilter;
        _logger = logger;
    }

    private CancellationToken Ct => HttpContext.RequestAborted;

    // =======================================================================
    // Shell + grid
    // =======================================================================

    // Views live under Views/Workforce, not Views/Employees - the controller
    // is named after the route ("employees"), the folder after the module
    // ("Workforce", alongside the Kuwait Compliance views it also owns), so
    // every action names its view explicitly rather than relying on the
    // {ControllerName} convention.
    private const string ViewsRoot = "~/Views/Workforce/";

    /// <summary>
    /// The employee an id names exists and is in the user's company (CompanyScope) - checked
    /// on every action that takes an employee id, so changing it in the address or a posted
    /// field cannot reach another company's employee.
    /// </summary>
    private async Task<bool> OwnsEmployeeAsync(long employeeId)
    {
        if (employeeId <= 0) return false;
        if (_currentUser.ActiveCompanyId is null) return true;
        var employee = await _employees.GetByIdAsync(employeeId, Ct);
        return employee is not null && _currentUser.Allows(employee.CompanyId);
    }

    private static IActionResult NotYours() =>
        new JsonResult(ActionResponse.Failed("That record was not found.", "NOT_FOUND"));

    [HttpGet("")]
    [HttpGet("index")]
    public IActionResult Index() => View(ViewsRoot + "Index.cshtml");

    [HttpGet("grid")]
    public async Task<IActionResult> Grid([FromQuery] GridRequest request)
    {
        // Scope the list to the user's active company once they have one,
        // same as every Organization Setup grid.
        // a pinned user's own company always wins over a CompanyId in the query string
        request.CompanyId = _currentUser.ActiveCompanyId ?? request.CompanyId;

        // Top-bar company filter (cookie) - always from the server, never the query string.
        request.CompanyIds = _companyFilter.Csv;

        var page = await _employees.ListAsync(request, Ct);

        return PartialView(ViewsRoot + "_EmployeesGrid.cshtml", new EmployeeGridViewModel
        {
            Page = page,
            Request = request
        });
    }

    // =======================================================================
    // Add - the Profile page in step-by-step mode (Personal -> Employment -> Compliance -> Dependents -> Documents)
    // =======================================================================

    /// <summary>
    /// A brand-new employee gets a dedicated wizard screen rather than the
    /// tabbed Profile page - the two are different jobs (walk someone
    /// through entering a new record vs. letting them jump straight to
    /// whichever section of an existing one they need), so they get
    /// different UIs even though they post to the same Save action.
    /// </summary>
    [HttpGet("add")]
    public async Task<IActionResult> Add()
    {
        // Pre-select the company when the top-bar filter is narrowed to exactly one.
        var employee = new Employee { CompanyId = _currentUser.ActiveCompanyId ?? _companyFilter.SingleCompanyId ?? 0 };
        var lookups = await LoadProfileLookupsAsync(includeInactive: false);

        // Same page as editing (every section, same fields) - shown as a
        // step-by-step wizard instead of tabs.
        return View(ViewsRoot + "Profile.cshtml", new EmployeeProfileViewModel
        {
            Employee = employee,
            IsNew = true,
            Wizard = true,
            ActiveTab = "personal",
            Lookups = lookups
        });
    }

    // =======================================================================
    // Profile - one page, tabbed sections (existing employees)
    // =======================================================================

    [HttpGet("profile/{id:long}")]
    [HttpGet("profile")]
    public async Task<IActionResult> Profile(long id = 0, string? tab = null, bool wizard = false)
    {
        // A new employee is created through the Add wizard, not this page -
        // redirect rather than 404 so an old profile/0 link still works.
        if (id <= 0)
        {
            return RedirectToAction(nameof(Add));
        }

        var employee = await _employees.GetByIdAsync(id, Ct);

        // another company's employee answers "not found", like a missing one
        if (employee is null || !_currentUser.Allows(employee.CompanyId))
        {
            return NotFound();
        }

        // Compliance is a separate 1:1 record that may not exist yet, even for
        // an existing employee - that is a normal state, rendered as an empty form.
        var compliance = await _compliance.GetAsync(id, Ct);
        var lookups = await LoadProfileLookupsAsync(includeInactive: true);

        return View(ViewsRoot + "Profile.cshtml", new EmployeeProfileViewModel
        {
            Employee = employee,
            Compliance = compliance,
            IsNew = false,
            Wizard = wizard,
            ActiveTab = string.IsNullOrWhiteSpace(tab) ? "personal" : tab,
            Lookups = lookups
        });
    }

    /// <summary>
    /// Dropdowns the Personal Info and Employment sections need, on both the
    /// Add wizard and the Profile page. <paramref name="includeInactive"/>
    /// is true for an existing employee so a value pointing at a since-
    /// deactivated row does not silently disappear from its dropdown.
    /// </summary>
    private async Task<Dictionary<string, IReadOnlyList<LookupItem>>> LoadProfileLookupsAsync(bool includeInactive)
    {
        var lookups = new Dictionary<string, IReadOnlyList<LookupItem>>(StringComparer.OrdinalIgnoreCase);

        foreach (var type in ProfileLookupTypes)
        {
            // a user pinned to a company only gets that company's lists
            lookups[type] = _currentUser.OwnCompanies(type, await _lookups.GetAsync(
                type,
                companyId: _currentUser.LookupCompany(null),
                parentId: null,
                includeInactive: includeInactive,
                cancellationToken: Ct));
        }

        return lookups;
    }

    // =======================================================================
    // Write actions
    // =======================================================================

    /// <summary>Saves Personal Info and Employment together - both tabs are one row.</summary>
    [HttpPost("save")]
    public async Task<IActionResult> Save()
    {
        var model = new Employee();

        if (!await TryUpdateModelAsync(model))
        {
            return Json(ActionResponse.Invalid(CollectErrors()));
        }

        // the employee (when editing) and the company chosen must both be the user's
        if (!_currentUser.Allows(model.CompanyId) || (model.EmployeeId > 0 && !await OwnsEmployeeAsync(model.EmployeeId)))
        {
            return NotYours();
        }

        var result = await _employees.SaveAsync(model, _currentUser.UserId, Ct);

        if (!result.Success)
        {
            _logger.LogInformation(
                "Employee save rejected by the database with {Code}.", result.ErrorCode);
        }

        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    /// <summary>Saves the Kuwait Compliance tab - a separate record, saved independently.</summary>
    [HttpPost("compliance/save")]
    public async Task<IActionResult> SaveCompliance()
    {
        var model = new EmployeeKuwaitCompliance();

        if (!await TryUpdateModelAsync(model))
        {
            return Json(ActionResponse.Invalid(CollectErrors()));
        }

        if (model.EmployeeId <= 0)
        {
            return Json(ActionResponse.Failed(
                "Save the employee's Personal Info first, then add Kuwait compliance details."));
        }

        if (!await OwnsEmployeeAsync(model.EmployeeId))
        {
            return NotYours();
        }

        var (code, message) = await _compliance.UpsertAsync(model, _currentUser.UserId, Ct);
        var success = string.Equals(code, ResultCode.Success, StringComparison.Ordinal);

        if (!success)
        {
            _logger.LogInformation("Kuwait compliance save rejected by the database with {Code}.", code);
        }

        return Json(success
            ? ActionResponse.Ok(model.EmployeeId, string.IsNullOrWhiteSpace(message) ? "Saved successfully." : message)
            : ActionResponse.Failed(
                string.IsNullOrWhiteSpace(message) ? "The operation could not be completed." : message, code));
    }

    // =======================================================================
    // Dependents - a one-to-many child list, loaded/saved independently of
    // both the Employee row and the Kuwait Compliance record. The grid slot
    // on the Dependents tab fetches _DependentsGrid.cshtml the same way the
    // Employees list fetches _EmployeesGrid.cshtml, and reloads it after
    // every add/edit/delete rather than manipulating rows in place.
    // =======================================================================

    [HttpGet("dependents/{employeeId:long}/grid")]
    public async Task<IActionResult> DependentsGrid(long employeeId)
    {
        if (!await OwnsEmployeeAsync(employeeId)) return NotFound();

        var dependents = await _dependents.ListAsync(employeeId, Ct);

        return PartialView(ViewsRoot + "Partials/_DependentsGrid.cshtml", dependents);
    }

    [HttpPost("dependents/save")]
    public async Task<IActionResult> SaveDependent()
    {
        var model = new EmployeeDependent();

        if (!await TryUpdateModelAsync(model))
        {
            return Json(ActionResponse.Invalid(CollectErrors()));
        }

        if (model.EmployeeId <= 0)
        {
            return Json(ActionResponse.Failed("Save the employee first, then add dependents."));
        }

        if (!await OwnsEmployeeAsync(model.EmployeeId))
        {
            return NotYours();
        }

        var result = await _dependents.SaveAsync(model, _currentUser.UserId, Ct);

        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    [HttpPost("dependents/delete")]
    public async Task<IActionResult> DeleteDependent(long id, long employeeId)
    {
        if (!await OwnsEmployeeAsync(employeeId)) return NotYours();

        var result = await _dependents.DeleteAsync(id, employeeId, _currentUser.UserId, Ct);

        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    // =======================================================================
    // Documents - every active document type grouped by Document Section,
    // with one upload slot per type. Same grid-slot pattern as Dependents:
    // the tab fetches _DocumentsGrid.cshtml and reloads it after each
    // upload/remove. Files are stored on disk by IDocumentStorage (outside
    // wwwroot); only metadata goes through Documents.usp_EmployeeDocument_Manage.
    // =======================================================================

    [HttpGet("documents/{employeeId:long}/grid")]
    public async Task<IActionResult> DocumentsGrid(long employeeId)
    {
        if (!await OwnsEmployeeAsync(employeeId)) return NotFound();

        var rows = await _documents.ListAsync(employeeId, Ct);

        return PartialView(ViewsRoot + "Partials/_DocumentsGrid.cshtml", new EmployeeDocumentsViewModel
        {
            EmployeeId = employeeId,
            Rows = rows,
            MaxFileSizeMb = (int)(_storage.MaxFileSizeBytes / 1024 / 1024)
        });
    }

    /// <summary>Uploads (or replaces) the file for one document type.</summary>
    [HttpPost("documents/upload")]
    [RequestSizeLimit(20 * 1024 * 1024)]
    [RequestFormLimits(MultipartBodyLengthLimit = 20 * 1024 * 1024)]
    public async Task<IActionResult> UploadDocument(long employeeId, int documentTypeId, IFormFile? file)
    {
        if (employeeId <= 0 || documentTypeId <= 0)
        {
            return Json(ActionResponse.Failed("Save the employee first, then upload documents."));
        }

        if (file is null)
        {
            return Json(ActionResponse.Failed("Choose a file to upload."));
        }

        if (!await OwnsEmployeeAsync(employeeId))
        {
            return NotYours();
        }

        var (stored, error) = await _storage.SaveAsync(employeeId, file, Ct);

        if (stored is null)
        {
            return Json(ActionResponse.Failed(error ?? "The file could not be saved."));
        }

        var result = await _documents.AddAsync(new EmployeeDocumentFile
        {
            EmployeeId = employeeId,
            DocumentTypeId = documentTypeId,
            OriginalFileName = stored.OriginalFileName,
            StoredFileName = stored.RelativePath,
            ContentType = stored.ContentType,
            FileSizeBytes = stored.SizeBytes
        }, _currentUser.UserId, Ct);

        if (!result.Success)
        {
            // Nothing points at the new file - don't leave it orphaned on disk.
            var orphan = _storage.Resolve(stored.RelativePath);
            if (orphan is not null)
            {
                System.IO.File.Delete(orphan);
            }

            _logger.LogInformation("Document upload rejected by the database with {Code}.", result.ErrorCode);
        }

        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    /// <summary>Streams one uploaded file - inline to view, or as an attachment to download.</summary>
    [HttpGet("documents/{employeeId:long}/file/{attachmentId:long}")]
    public async Task<IActionResult> DocumentFile(long employeeId, long attachmentId, bool download = false)
    {
        if (!await OwnsEmployeeAsync(employeeId)) return NotFound();

        var file = await _documents.GetAsync(employeeId, attachmentId, Ct);
        var path = file is null ? null : _storage.Resolve(file.StoredFileName);

        if (file is null || path is null)
        {
            return NotFound();
        }

        // Uploaded content is not app markup: lock it down harder than a page,
        // and never let a browser or proxy keep a copy of an ID document.
        Response.Headers["Content-Security-Policy"] = "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; object-src 'self'; frame-ancestors 'none'";
        Response.Headers.CacheControl = "private, no-store, max-age=0";

        return PhysicalFile(
            path,
            file.ContentType,
            fileDownloadName: download ? file.OriginalFileName : null,
            enableRangeProcessing: true);
    }

    [HttpPost("documents/delete")]
    public async Task<IActionResult> DeleteDocument(long id, long employeeId)
    {
        if (!await OwnsEmployeeAsync(employeeId)) return NotYours();

        // Soft delete: the row and the file on disk are kept as history.
        var result = await _documents.DeleteAsync(employeeId, id, _currentUser.UserId, Ct);

        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    [HttpPost("delete")]
    public async Task<IActionResult> Delete(long id)
    {
        if (!await OwnsEmployeeAsync(id)) return NotYours();

        var result = await _employees.DeleteAsync(id, _currentUser.UserId, Ct);

        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    [HttpPost("toggle")]
    public async Task<IActionResult> Toggle(long id)
    {
        if (!await OwnsEmployeeAsync(id)) return NotYours();

        var result = await _employees.ToggleActiveAsync(id, _currentUser.UserId, Ct);

        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    private Dictionary<string, string[]> CollectErrors() =>
        ModelState
            .Where(entry => entry.Value?.Errors.Count > 0)
            .ToDictionary(
                entry => entry.Key,
                entry => entry.Value!.Errors.Select(e => e.ErrorMessage).ToArray());
}
